import Persistence
import SwiftUI
import WingspotCore

/// Shown after the server unlocks a badge level, with a haptic.
struct CelebrationView: View {
    let celebrations: [Celebration]
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(celebrations.count == 1 ? "New badge!" : "New badges!")
                .font(.largeTitle.bold())
                .padding(.top, 32)
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(celebrations) { celebration in
                        VStack(spacing: 10) {
                            BadgeIcon(badge: celebration.badge, size: 88)
                                .symbolEffect(.bounce, value: celebration.id)
                            Text(localized(celebration.badge.name)).font(.title2.bold())
                            if !celebration.badge.isSingle {
                                Text("Level \(celebration.badge.level)")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }
                            if let description = celebration.badge.description {
                                Text(localized(description))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal)
            }
            Button(action: onDone) {
                Text("Nice!").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding([.horizontal, .bottom])
        }
        .sensoryFeedback(.success, trigger: celebrations.map(\.id))
    }
}
