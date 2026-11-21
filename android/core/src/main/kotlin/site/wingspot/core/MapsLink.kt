package site.wingspot.core

import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** The position in a link or text copied from a maps app. */
object MapsLink {
    private const val NUMBER = "(-?\\d{1,3}(?:\\.\\d+)?)"
    private const val LOOSE = "(-?\\d{1,3}(?:[.,]\\d+)?)"
    private val patterns = listOf(
        Regex("!3d$NUMBER!4d$NUMBER"),
        Regex("@$NUMBER,$NUMBER"),
        Regex("[?&](?:ll|q|query|center|sll|destination|coordinate)=$NUMBER(?:,|%2C)$NUMBER"),
        Regex("^[\\s(\\[]*$NUMBER\\s*[,;]\\s*$NUMBER[\\s)\\]]*$"),
    )
    /** `51.2805, 6.7699`, or `51,28050° N, 6,76986° O` (comma as decimal mark, N/S/E/O/W). */
    private val plain = Regex("^[\\s(\\[]*$LOOSE\\s*°?\\s*([NSns])?\\s*[,;]?\\s*$LOOSE\\s*°?\\s*([EOWeow])?\\s*\\.?[\\s)\\]]*$")
    private val pageCoordinate = Regex("coordinate=$NUMBER,\\s?$NUMBER")
    private val shortLinkHosts = setOf("maps.apple", "maps.apple.com", "maps.app.goo.gl", "goo.gl")

    private fun valid(latitude: Double?, longitude: Double?): Pair<Double, Double>? =
        if (latitude != null && longitude != null && kotlin.math.abs(latitude) <= 90 && kotlin.math.abs(longitude) <= 180) latitude to longitude else null

    private fun pair(pattern: Regex, text: String): Pair<Double, Double>? {
        val m = pattern.find(text) ?: return null
        return valid(m.groupValues[1].toDoubleOrNull(), m.groupValues[2].toDoubleOrNull())
    }

    /** Latitude and longitude, or null when the text has none or an impossible one. */
    fun coordinate(text: String): Pair<Double, Double>? {
        for (pattern in patterns) pair(pattern, text)?.let { return it }
        val m = plain.find(text) ?: return null
        var latitude = m.groupValues[1].replace(',', '.').toDoubleOrNull()
        var longitude = m.groupValues[3].replace(',', '.').toDoubleOrNull()
        if (m.groupValues[2].uppercase() == "S") latitude = latitude?.let { -kotlin.math.abs(it) }
        if (m.groupValues[4].uppercase() == "W") longitude = longitude?.let { -kotlin.math.abs(it) }
        return valid(latitude, longitude)
    }

    /** Like [coordinate], and for the short links of Apple Maps and Google Maps (which carry no position) it opens the link to find it. */
    suspend fun resolve(text: String): Pair<Double, Double>? {
        coordinate(text)?.let { return it }
        val link = Regex("https://[^\\s]+").find(text)?.value ?: return null
        val url = try { URL(link) } catch (e: Exception) { return null }
        if (url.host.lowercase() !in shortLinkHosts) return null
        return withContext(Dispatchers.IO) {
            try {
                val connection = (url.openConnection() as HttpURLConnection).apply {
                    connectTimeout = 8000; readTimeout = 8000; instanceFollowRedirects = true
                    setRequestProperty("User-Agent", "Mozilla/5.0")
                }
                try {
                    val stream = if (connection.responseCode >= 400) connection.errorStream else connection.inputStream
                    val page = stream?.use { it.readNBytes(600_000).toString(Charsets.UTF_8) } ?: ""
                    coordinate(connection.url.toString()) ?: pair(pageCoordinate, page)
                } finally { connection.disconnect() }
            } catch (e: Exception) { null }
        }
    }
}
