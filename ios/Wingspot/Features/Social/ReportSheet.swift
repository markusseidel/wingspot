import Account
import SwiftUI

/// What is being reported. Used to open `ReportSheet`.
struct ReportTarget: Identifiable {
    let kind: ReportKind
    let id: UUID
    /// What the sheet asks about, such as "@anna" or "this comment".
    let subject: LocalizedStringResource
}

extension ReportReason {
    var title: LocalizedStringKey {
        switch self {
        case .spam: "Spam or advertising"
        case .offensive: "Offensive, hateful or harassing"
        case .privacy: "Shows private information"
        case .other: "Something else"
        }
    }
}

/// Asks why, then sends the report. The owner reads reports and removes what breaks the rules.
struct ReportSheet: View {
    let target: ReportTarget

    @Environment(Reporter.self) private var reporter
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ReportReason.offensive
    @State private var details = ""
    @State private var isSending = false
    @State private var sent = false
    @State private var failure: AccountError?

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section {
                        Label("Thank you. We'll look at your report.", systemImage: "checkmark.circle")
                    } footer: {
                        Text("You can also block someone on their profile, so you don't see them anymore.")
                    }
                } else {
                    Section {
                        Picker("Reason", selection: $reason) {
                            ForEach(ReportReason.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        Text("Why do you want to report \(String(localized: target.subject))?")
                            .textCase(nil)
                    }
                    Section("Details (optional)") {
                        TextField("What happened?", text: $details, axis: .vertical)
                            .lineLimit(2...6)
                    }
                    if let failure {
                        Section { Text(failure.message).foregroundStyle(.red) }
                    }
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                }
                if !sent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") { send() }.disabled(isSending)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() {
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await reporter.report(target.kind, target: target.id, reason: reason, details: String(details.prefix(900)))
                sent = true
                failure = nil
            } catch {
                failure = (error as? AccountError) ?? .unknown
            }
        }
    }
}
