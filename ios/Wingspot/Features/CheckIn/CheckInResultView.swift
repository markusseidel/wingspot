import Persistence
import SwiftUI

/// The reward after saving (concept §4.1). Badges join this screen once they exist.
struct CheckInResultView: View {
    let result: SpottedResult
    let onAnother: () -> Void
    let onDone: () -> Void

    private var isFirstTime: Bool { result.history == .firstTime }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: isFirstTime ? "sparkles" : "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(result.subject)
                    .font(.system(.largeTitle, design: .monospaced).bold())
                Text(headline)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                if let detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
            VStack(spacing: 12) {
                Button(action: onAnother) {
                    Text("Check in another").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: onDone) {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .padding()
        .sensoryFeedback(.success, trigger: result.id)
    }

    private var headline: String {
        switch result.history {
        case .firstTime:
            "First time seeing this one!"
        case .seenBefore(let count, _, _):
            "Seen for the \(Self.ordinal(count)) time"
        }
    }

    private var detail: String? {
        guard case .seenBefore(_, let lastSeen, let lastPlace) = result.history else { return nil }
        let date = lastSeen.formatted(date: .abbreviated, time: .omitted)
        return lastPlace.map { "Last time at \($0), \(date)" } ?? "Last time on \(date)"
    }

    private static func ordinal(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: number as NSNumber) ?? "\(number)"
    }
}

#Preview("First") {
    CheckInResultView(result: .preview(.firstTime), onAnother: {}, onDone: {})
}

#Preview("Again") {
    CheckInResultView(
        result: .preview(.seenBefore(count: 4, lastSeen: .now, lastPlace: "FRA")), onAnother: {}, onDone: {}
    )
}

private extension SpottedResult {
    static func preview(_ history: History) -> SpottedResult {
        SpottedResult(id: UUID(), subject: "D-AIMA", history: history)
    }
}
