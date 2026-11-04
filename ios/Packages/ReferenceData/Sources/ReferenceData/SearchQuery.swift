import Foundation

enum SearchQuery {
    /// Builds an FTS5 prefix query, or `nil` if the text holds nothing searchable.
    ///
    /// Names like `CRJ-900` are stored as two words, so `crj900` also searches for `crj` and `900`.
    static func fts(_ text: String) -> String? {
        let tokens = text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        guard !tokens.isEmpty else { return nil }
        return tokens.map(clause(for:)).joined(separator: " ")
    }

    private static func clause(for token: String) -> String {
        let parts = splitLettersAndDigits(token)
        guard parts.count > 1 else { return "\"\(token)\"*" }
        let split = parts.map { "\"\($0)\"*" }.joined(separator: " ")
        return "(\"\(token)\"* OR (\(split)))"
    }

    private static func splitLettersAndDigits(_ token: String) -> [String] {
        var parts: [String] = []
        for character in token {
            if let last = parts.last?.last, last.isNumber == character.isNumber {
                parts[parts.count - 1].append(character)
            } else {
                parts.append(String(character))
            }
        }
        return parts
    }
}
