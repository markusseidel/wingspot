import Account
import SwiftUI

extension AccountError {
    var message: LocalizedStringResource {
        switch self {
        case .invalidEmail: "Please enter a valid email address."
        case .invalidUsername: "Use 3 to 30 lowercase letters, numbers or underscores."
        case .usernameTaken: "This username is taken. Please try another one."
        case .invalidLink: "This sign-in link doesn't work anymore. Please request a new one on this device."
        case .tooManyRequests: "Too many attempts. Please wait a moment and try again."
        case .appleUnavailable: "Sign in with Apple isn't available yet. Please use your email."
        case .offline: "You're offline. Please connect to the internet and try again."
        case .contentNotAllowed: "This comment isn't allowed. Please rephrase it."
        case .notConfigured: "Sign-in isn't available in this version of the app."
        case .unknown: "Something went wrong. Please try again."
        }
    }
}

extension Error {
    var accountMessage: LocalizedStringResource {
        ((self as? AccountError) ?? .unknown).message
    }
}

extension View {
    /// Tells the user when a sign-in link failed. Only the topmost screen can show an alert.
    func signInLinkAlert(isEnabled: Bool) -> some View {
        modifier(SignInLinkAlert(isEnabled: isEnabled))
    }
}

private struct SignInLinkAlert: ViewModifier {
    let isEnabled: Bool
    @Environment(AccountStore.self) private var account

    func body(content: Content) -> some View {
        content.alert(
            "Couldn't sign in",
            isPresented: Binding(
                get: { isEnabled && account.linkError != nil },
                set: { if !$0 { account.linkError = nil } }
            ),
            presenting: account.linkError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }
}
