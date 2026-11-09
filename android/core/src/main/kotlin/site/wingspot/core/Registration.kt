package site.wingspot.core

/**
 * An aircraft registration in canonical form, e.g. `D-AIMA`, `N123AB`, `JA8089`. The rules are the iPhone app's
 * and are checked against `contracts/test-vectors/registrations.json`.
 */
class Registration private constructor(val value: String, val prefix: String, val countryCode: String) {
    override fun toString() = value
    override fun equals(other: Any?) = other is Registration && other.value == value
    override fun hashCode() = value.hashCode()

    companion object {
        private const val ALLOWED = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789- "

        /** Parses `daima`, `D AIMA` or `d-aima`. Null if it isn't a valid registration. */
        fun parse(input: String): Registration? {
            val text = input.trim().uppercase()
            if (text.isEmpty() || text.any { it !in ALLOWED }) return null

            val parts = text.split('-', ' ')
            val prefix: String
            val mark: String
            when (parts.size) {
                1 -> {
                    // No separator: prefer the longer prefix (`HBJNA` is `HB`), then single letters (`DAIMA` is `D`).
                    val match = listOf(2, 1).map { text.take(it) }
                        .firstOrNull { it.length < text.length && NationalityPrefix.all[it] != null } ?: return null
                    prefix = match
                    mark = text.drop(match.length)
                }
                2 -> {
                    prefix = parts[0]
                    mark = parts[1]
                }
                else -> return null
            }
            val entry = NationalityPrefix.all[prefix] ?: return null
            if (!isValidMark(mark, prefix)) return null
            val value = if (entry.usesDash) "$prefix-$mark" else prefix + mark
            return Registration(value, prefix, entry.countryCode(mark))
        }

        private fun isValidMark(mark: String, prefix: String): Boolean {
            if (mark.isEmpty() || '-' in mark || ' ' in mark) return false
            if (prefix == "N") {
                // US: N plus 1 to 5 characters, the first a digit 1 to 9.
                val first = mark.first()
                return first in '1'..'9' && mark.length <= 5
            }
            return mark.length <= 6
        }
    }
}
