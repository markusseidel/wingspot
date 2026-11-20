package site.wingspot.core

/** The invite link: `wingspot://invite/CODE`. */
object InviteLink {
    private const val ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    fun url(code: String) = "wingspot://invite/$code"

    /** The code in an invite link, or null if this is not one. */
    fun code(link: String): String? {
        val prefix = "wingspot://invite/"
        if (!link.startsWith(prefix)) return null
        return clean(link.removePrefix(prefix).substringBefore('?').substringBefore('#'))
    }

    /** A typed or pasted code made tidy: trimmed, upper case, and only if it has the right shape. */
    fun clean(text: String): String? {
        val code = text.trim().uppercase()
        return if (code.length == 8 && code.all { it in ALPHABET }) code else null
    }
}
