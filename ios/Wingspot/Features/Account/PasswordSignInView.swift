import Account
import SwiftUI

/// Sign-in with an email and a password, for the demo account App Review uses. Nobody else has a password.
struct PasswordSignInView: View {
    @Environment(AccountStore.self) private var account
    @State private var email = ""
    @State private var password = ""
    @State private var isSigning = false
    @State private var error: LocalizedStringResource?

    var body: some View {
        Form {
            Section {
                TextField("Email address", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit(signIn)
            } footer: {
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            Section {
                Button(action: signIn) {
                    if isSigning {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Sign in")
                    }
                }
                .disabled(isSigning || email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
            }
        }
        .navigationTitle("Password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func signIn() {
        guard !isSigning else { return }
        isSigning = true
        error = nil
        Task {
            defer { isSigning = false }
            do {
                try await account.signInWithPassword(email: email, password: password)
            } catch {
                self.error = error.accountMessage
            }
        }
    }
}
