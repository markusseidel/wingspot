import Account
import AuthenticationServices
import SwiftUI

/// Sign in with Apple. Apple checks the user, and the backend turns the identity token into a session.
struct AppleSignInButton: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    @State private var nonce = ""
    @State private var error: AccountError?

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            // A new nonce for each attempt.
            nonce = Nonce.random()
            request.requestedScopes = [.fullName, .email]
            request.nonce = Nonce.sha256(nonce)
        } onCompletion: { result in
            handle(result)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 50)
        // The same round shape as the other sign-in buttons.
        .clipShape(Capsule())
        .alert(
            "Couldn't sign in",
            isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }),
            presenting: error
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let failure):
            // Closing Apple's sheet is not an error.
            if (failure as? ASAuthorizationError)?.code == .canceled { return }
            error = .unknown
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken,
                  let token = String(data: data, encoding: .utf8) else {
                error = .unknown
                return
            }
            let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
            let nonce = nonce
            Task {
                do {
                    try await account.signInWithApple(idToken: token, nonce: nonce, fullName: name)
                } catch {
                    self.error = (error as? AccountError) ?? .unknown
                }
            }
        }
    }
}
