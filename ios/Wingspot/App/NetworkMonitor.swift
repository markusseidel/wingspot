import Network

/// Calls `onReconnect` when the network comes back, so waiting check-ins go up without the user doing anything.
final class NetworkMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "site.wingspot.ios.network")
    // Only touched on `queue`.
    private var wasOnline: Bool?

    func start(onReconnect: @escaping @Sendable () -> Void) {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let isOnline = path.status == .satisfied
            // The first update reports the state at launch, which the app handles itself.
            if wasOnline == false, isOnline { onReconnect() }
            wasOnline = isOnline
        }
        monitor.start(queue: queue)
    }
}
