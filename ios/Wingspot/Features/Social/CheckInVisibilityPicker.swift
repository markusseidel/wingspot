import Account
import SwiftUI

/// "Who can see this" for one check-in of yours: its own level, or "same as my sharing setting". Saved at once.
/// Shows nothing until the check-in is known to the server.
struct CheckInVisibilityPicker: View {
    let checkInID: UUID

    @Environment(CheckInVisibilityStore.self) private var store
    @State private var current: CheckInVisibility?
    @State private var failure: AccountError?

    /// What the picker shows: nil is "same as my sharing setting".
    private var selection: Binding<SharingChoice?> {
        Binding(
            get: { current?.isCustom == true ? current?.level : nil },
            set: { new in Task { await set(new) } }
        )
    }

    var body: some View {
        Group {
            if let current {
                Picker("Who can see this", selection: selection) {
                    Text("Same as my sharing setting").tag(SharingChoice?.none)
                    ForEach(SharingChoice.allCases, id: \.self) { Text($0.title).tag(SharingChoice?.some($0)) }
                }
                .accessibilityIdentifier("visibility-picker")
                if !current.isCustom {
                    Text("Follows your sharing setting: \(Text(current.level.title))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: checkInID) { current = try? await store.visibility(of: checkInID) }
        .alert("Couldn't complete this", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if let failure { Text(failure.message) }
        }
    }

    private func set(_ choice: SharingChoice?) async {
        do {
            if let updated = try await store.set(choice, for: checkInID) { current = updated }
        } catch let error as AccountError {
            failure = error
        } catch {
            failure = .unknown
        }
    }
}
