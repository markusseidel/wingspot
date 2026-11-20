package site.wingspot.core

/** Reading and writing @mentions in comment text. Usernames are lowercase letters, digits and underscores. */
object CommentText {
    private fun isNameChar(c: Char) = c in 'a'..'z' || c in 'A'..'Z' || c in '0'..'9' || c == '_'

    /**
     * What the person has typed after an "@" at the end of [text], if they are in the middle of a name: "hello @ma"
     * gives "ma", "hello @" gives "", "hello" gives null. The "@" must start a word.
     */
    fun activePrefix(text: String): String? {
        var i = text.length
        while (i > 0) {
            val c = text[i - 1]
            if (c == '@') {
                if (i - 1 > 0 && isNameChar(text[i - 2])) return null
                return text.substring(i).lowercase()
            }
            if (!isNameChar(c)) return null
            i--
        }
        return null
    }

    /** [text] with the name being typed at its end replaced by the whole `@username ` (with a space after it). */
    fun completing(text: String, username: String): String {
        val prefix = activePrefix(text) ?: return text
        return text.dropLast(prefix.length + 1) + "@" + username + " "
    }

    /** A reply: [text] starts with the name of the person answered, unless it already does. */
    fun replying(username: String, text: String): String {
        val start = "@$username "
        return if (text.lowercase().startsWith(start.lowercase())) text else start + text
    }

    /** Where `@username` stands in [body], for each of [usernames]. Case does not matter; the name must end at a word boundary. */
    fun mentionRanges(body: String, usernames: Collection<String>): List<Pair<IntRange, String>> {
        val found = mutableListOf<Pair<IntRange, String>>()
        for (name in usernames) {
            val needle = "@$name"
            var from = 0
            while (true) {
                val at = body.indexOf(needle, from, ignoreCase = true)
                if (at < 0) break
                from = at + needle.length
                val startsWord = at == 0 || !isNameChar(body[at - 1])
                val endsWord = from >= body.length || !isNameChar(body[from])
                if (startsWord && endsWord) found += (at until from) to name
            }
        }
        return found.sortedBy { it.first.first }
    }
}
