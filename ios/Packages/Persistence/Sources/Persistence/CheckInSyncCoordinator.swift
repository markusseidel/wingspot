import Foundation
import Observation

/// Decides when the outbox runs. Callers just say "sync now" after a save, on coming to the
/// foreground, after sign-in and when the network returns. Several requests at once become one run,
/// and a run that fails because of the network tries again after a growing pause, then stops
/// until the next request.
@MainActor
@Observable
public final class CheckInSyncCoordinator {
    public static let defaultBackoff: [Duration] = [.seconds(5), .seconds(30), .seconds(120), .seconds(600)]

    private let outbox: CheckInOutbox
    private let photos: PhotoOutbox?
    private let userID: @MainActor () -> UUID?
    private let sleep: @Sendable (Duration) async -> Void
    private let backoff: [Duration]
    private let afterRun: @MainActor () -> Void
    private var task: Task<Void, Never>?
    private var requestedAgain = false

    /// Check-ins that failed on the last run and will be retried.
    public private(set) var isWaitingToRetry = false

    public init(
        outbox: CheckInOutbox,
        photos: PhotoOutbox? = nil,
        userID: @escaping @MainActor () -> UUID?,
        backoff: [Duration] = CheckInSyncCoordinator.defaultBackoff,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        afterRun: @escaping @MainActor () -> Void = {}
    ) {
        self.outbox = outbox
        self.photos = photos
        self.userID = userID
        self.backoff = backoff
        self.afterRun = afterRun
        self.sleep = sleep
    }

    /// Does nothing while signed out: check-ins wait on the device and go up after sign-in.
    public func requestSync() {
        guard task == nil else {
            requestedAgain = true
            return
        }
        task = Task { await run() }
    }

    /// For tests: resolves when the current run, if any, has finished.
    public func waitUntilIdle() async {
        while let task { await task.value }
    }

    /// Anything that has to be tried again makes the whole run try again.
    private static func combined(_ checkIns: OutboxOutcome, _ photos: OutboxOutcome?) -> OutboxOutcome {
        if case .retryLater = checkIns { return checkIns }
        if let photos, case .retryLater = photos { return photos }
        return checkIns
    }

    private func run() async {
        defer {
            task = nil
            isWaitingToRetry = false
        }
        var failures = 0
        while true {
            requestedAgain = false
            guard let id = userID() else { return }
            // Check-ins first, because a photo goes up only after its check-in is stored.
            let checkIns = await outbox.sync(userID: id)
            let pictures = await photos?.sync(userID: id)
            switch Self.combined(checkIns, pictures) {
            case .idle, .finished:
                failures = 0
                isWaitingToRetry = false
                // Whether something went up or not, the server may know something new, such as badges.
                afterRun()
                // Something may have been saved while this run was uploading.
                if !requestedAgain { return }
            case .retryLater:
                guard failures < backoff.count else { return }
                isWaitingToRetry = true
                await sleep(backoff[failures])
                failures += 1
                if Task.isCancelled { return }
            }
        }
    }
}
