import Foundation

/// An aircraft registration (tail number) in canonical form, e.g. `D-AIMA`, `N123AB`, `JA8089`.
///
/// Normalization rules are shared with the Android app and checked against
/// `contracts/test-vectors/registrations.json`.
public struct Registration: Hashable, Sendable, Codable, CustomStringConvertible {
    /// Canonical form: uppercase, dash after the nationality prefix unless the register writes none.
    public let value: String
    /// Nationality prefix, e.g. `D`, `HB`, `9H`.
    public let prefix: String
    /// ISO 3166-1 alpha-2 code of the register, e.g. `DE`.
    public let countryCode: String

    public var description: String { value }

    /// Parses user input such as `daima`, `D AIMA` or `d-aima`. Returns `nil` if the input is not a valid registration.
    public init?(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !text.isEmpty,
              text.unicodeScalars.allSatisfy({ Self.allowed.contains($0) })
        else { return nil }

        let parts = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "-" || $0 == " " })
        let prefix: String
        let mark: String
        switch parts.count {
        case 1:
            // No separator: prefer the longer prefix (`HBJNA` → `HB`), then single letters (`DAIMA` → `D`).
            guard let match = [2, 1].lazy
                .map({ String(text.prefix($0)) })
                .first(where: { $0.count < text.count && NationalityPrefix.all[$0] != nil })
            else { return nil }
            prefix = match
            mark = String(text.dropFirst(match.count))
        case 2:
            prefix = String(parts[0])
            mark = String(parts[1])
        default:
            return nil
        }

        guard let entry = NationalityPrefix.all[prefix], Self.isValidMark(mark, prefix: prefix) else { return nil }
        self.prefix = prefix
        self.value = entry.usesDash ? "\(prefix)-\(mark)" : prefix + mark
        self.countryCode = entry.countryCode(for: mark)
    }

    private static let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789- ")

    private static func isValidMark(_ mark: String, prefix: String) -> Bool {
        guard !mark.isEmpty, !mark.contains("-"), !mark.contains(" ") else { return false }
        if prefix == "N" {
            // US: N + 1–5 characters, first one a digit 1–9.
            guard let first = mark.first, ("1"..."9").contains(first) else { return false }
            return mark.count <= 5
        }
        return mark.count <= 6
    }
}
