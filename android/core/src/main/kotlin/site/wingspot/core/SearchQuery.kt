package site.wingspot.core

/** Builds the full-text queries for the reference database, the same way as the iPhone app. */
internal object SearchQuery {
    /**
     * An FTS5 prefix query, or null if the text holds nothing searchable. Names like `CRJ-900` are stored as two
     * words, so `crj900` also searches for `crj` and `900`.
     */
    fun fts(text: String): String? {
        val tokens = text.lowercase().split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }
        if (tokens.isEmpty()) return null
        return tokens.joinToString(" ") { clause(it) }
    }

    private fun clause(token: String): String {
        val parts = splitLettersAndDigits(token)
        if (parts.size <= 1) return "\"$token\"*"
        val split = parts.joinToString(" ") { "\"$it\"*" }
        return "(\"$token\"* OR ($split))"
    }

    private fun splitLettersAndDigits(token: String): List<String> {
        val parts = mutableListOf<StringBuilder>()
        for (c in token) {
            val last = parts.lastOrNull()?.last()
            if (last != null && last.isDigit() == c.isDigit()) parts.last().append(c) else parts += StringBuilder().append(c)
        }
        return parts.map { it.toString() }
    }
}
