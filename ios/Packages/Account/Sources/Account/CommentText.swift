import Foundation

/// Reading and writing @mentions in comment text. Usernames are lowercase letters, digits and underscores.
public enum CommentText {
    private static func isNameCharacter(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber || c == "_")
    }

    /// What the person has typed after an "@" at the end of `text`, if they are in the middle of a name:
    /// "hello @ma" gives "ma", "hello @" gives "", "hello" gives nil. The "@" must start a word.
    public static func activePrefix(in text: String) -> String? {
        var typed = ""
        var index = text.endIndex
        while index > text.startIndex {
            let before = text.index(before: index)
            let character = text[before]
            if character == "@" {
                if before > text.startIndex, isNameCharacter(text[text.index(before: before)]) { return nil }
                return typed.lowercased()
            }
            guard isNameCharacter(character) else { return nil }
            typed = String(character) + typed
            index = before
        }
        return nil
    }

    /// `text` with the name being typed at its end replaced by the whole `@username ` (with a space after it).
    public static func completing(_ text: String, with username: String) -> String {
        guard let prefix = activePrefix(in: text) else { return text }
        return String(text.dropLast(prefix.count + 1)) + "@" + username + " "
    }

    /// A reply: `text` starts with the name of the person answered, unless it already does.
    public static func replying(to username: String, in text: String) -> String {
        let start = "@" + username + " "
        return text.lowercased().hasPrefix(start.lowercased()) ? text : start + text
    }

    /// Where `@username` stands in `body`, for each of `usernames`. Case does not matter, and the name must end at a
    /// word boundary ("@max" is not found inside "@maxine").
    public static func mentionRanges(in body: String, usernames: [String]) -> [(range: Range<String.Index>, username: String)] {
        var found: [(Range<String.Index>, String)] = []
        for name in usernames {
            let needle = "@" + name
            var from = body.startIndex
            while let range = body.range(of: needle, options: .caseInsensitive, range: from..<body.endIndex) {
                from = range.upperBound
                let startsWord = range.lowerBound == body.startIndex || !isNameCharacter(body[body.index(before: range.lowerBound)])
                let endsWord = range.upperBound == body.endIndex || !isNameCharacter(body[range.upperBound])
                if startsWord && endsWord { found.append((range, name)) }
            }
        }
        return found.sorted { $0.0.lowerBound < $1.0.lowerBound }
    }
}
