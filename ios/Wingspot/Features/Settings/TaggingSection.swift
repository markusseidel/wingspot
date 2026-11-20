import Account
import SwiftUI

/// The setting for whether friends may tag you on their flights and airport visits. It is on by default.
struct TaggingSection: View {
    @Environment(FeedStore.self) private var feed
    @State private var allowed: Bool?
    @State private var failed = false

    var body: some View {
        Section {
            Toggle("Friends may tag me", isOn: Binding(
                get: { allowed ?? true },
                set: { new in
                    let before = allowed
                    allowed = new
                    Task {
                        if await !feed.setAllowsTags(new) {
                            allowed = before
                            failed = true
                        }
                    }
                }
            ))
            .disabled(allowed == nil)
        } footer: {
            Text("Only friends can tag you. A tagged friend's check-in shows you on it, and you can remove yourself from it at any time.")
        }
        .task { allowed = await feed.allowsTags() }
        .alert("Couldn't change this setting", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please check your connection and try again.")
        }
    }
}
