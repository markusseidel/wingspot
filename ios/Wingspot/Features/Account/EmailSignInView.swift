import Account
import SwiftUI

/// Requests a sign-in link. Opening the link in the email finishes sign-in, see `AccountStore.handle`.
struct EmailSignInView: View {
    @Environment(AccountStore.self) private var account
    @State private var email = ""
    @State private var sentTo: String?
    @State private var isSending = false
    @State private var error: LocalizedStringResource?
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if let sentTo {
                linkSent(to: sentTo)
            } else {
                form
            }
        }
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var form: some View {
        Form {
            Section {
                TextField("Email address", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .focused($isFocused)
                    .onSubmit(send)
            } footer: {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("We'll email you a link to sign in. You don't need a password.")
                }
            }
            Section {
                Button(action: send) {
                    if isSending {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Send link")
                    }
                }
                .disabled(isSending || email.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            LegalLinksSection(compact: true)
        }
        .onAppear { isFocused = true }
    }

    private func linkSent(to address: String) -> some View {
        ContentUnavailableView {
            Label("Check your email", systemImage: "envelope.open")
        } description: {
            Text("We sent a link to \(address). Open it on this iPhone to sign in.")
        } actions: {
            Button("Use a different email") {
                sentTo = nil
            }
        }
    }

    private func send() {
        guard !isSending else { return }
        isSending = true
        error = nil
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = Locale.current.language.languageCode?.identifier
        Task {
            defer { isSending = false }
            do {
                try await account.sendSignInLink(email: address, language: language)
                sentTo = address
            } catch {
                self.error = error.accountMessage
            }
        }
    }
}
