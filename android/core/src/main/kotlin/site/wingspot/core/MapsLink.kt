package site.wingspot.core

/** The position in a link or text copied from a maps app. Only text that carries the position is understood. */
object MapsLink {
    private const val NUMBER = "(-?\\d{1,3}(?:\\.\\d+)?)"
    private val patterns = listOf(
        Regex("!3d$NUMBER!4d$NUMBER"),
        Regex("@$NUMBER,$NUMBER"),
        Regex("[?&](?:ll|q|query|center|sll|destination)=$NUMBER(?:,|%2C)$NUMBER"),
        Regex("^\\s*$NUMBER\\s*[,;]\\s*$NUMBER\\s*$"),
    )

    /** Latitude and longitude, or null when the text has none or an impossible one. */
    fun coordinate(text: String): Pair<Double, Double>? {
        for (pattern in patterns) {
            val m = pattern.find(text) ?: continue
            val latitude = m.groupValues[1].toDoubleOrNull() ?: continue
            val longitude = m.groupValues[2].toDoubleOrNull() ?: continue
            if (kotlin.math.abs(latitude) <= 90 && kotlin.math.abs(longitude) <= 180) return latitude to longitude
        }
        return null
    }
}
