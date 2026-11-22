package site.wingspot.app

import android.content.Context
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import site.wingspot.core.KmlFlight
import site.wingspot.core.KmlFlightException
import site.wingspot.core.KmlFlightParser

/** What reading a KML file the person picked gave. */
sealed class KmlRead {
    data class Done(val flight: KmlFlight) : KmlRead()
    /** [title] and [message] are string resources for the alert. */
    data class Problem(val title: Int, val message: Int) : KmlRead()
}

object KmlImport {
    /** The biggest file that is read, in bytes. */
    const val SIZE_LIMIT = 50_000_000

    /** Reads and parses the file. It is read on this phone and nothing is sent anywhere. */
    suspend fun read(context: Context, uri: Uri): KmlRead = withContext(Dispatchers.IO) {
        val bytes = try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                val out = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    out.write(buffer, 0, n)
                    if (out.size() > SIZE_LIMIT) return@withContext KmlRead.Problem(R.string.kml_large_title, R.string.kml_large_message)
                }
                out.toByteArray()
            }
        } catch (e: java.io.IOException) {
            null
        } catch (e: SecurityException) {
            null
        } ?: return@withContext KmlRead.Problem(R.string.kml_unreadable_title, R.string.kml_unreadable_message)
        try {
            KmlRead.Done(KmlFlightParser.parse(String(bytes, Charsets.UTF_8)))
        } catch (e: KmlFlightException) {
            KmlRead.Problem(R.string.kml_not_title, R.string.kml_not_message)
        }
    }
}
