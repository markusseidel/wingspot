import CryptoKit
import Foundation

/// The random value that ties a Sign in with Apple request to its answer. Apple puts the SHA-256 of it into the
/// identity token, and the backend checks it against the original, so a stolen token can't be replayed.
public enum Nonce {
    // 64 characters, so a random byte maps to one without bias.
    private static let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-.")

    public static func random(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        precondition(status == errSecSuccess, "The system couldn't make random bytes")
        return String(bytes.map { characters[Int($0) % characters.count] })
    }

    /// Lowercase hex, which is what Apple expects in `ASAuthorizationAppleIDRequest.nonce`.
    public static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
