package site.wingspot.app

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import java.util.UUID
import kotlinx.coroutines.launch
import site.wingspot.core.FlightTrack
import site.wingspot.core.GeoCoordinate
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

private class PendingRoute(val track: List<GeoCoordinate>, val message: String)

/**
 * On the page of your own flight: adds the route from a KML file, or replaces the one that is saved. Nothing else on the
 * flight changes, and nothing is saved before the person confirms. The route stays on this phone.
 */
@Composable
fun RouteFromFile(
    app: WingspotApp, flightId: UUID, originCode: String?, destinationCode: String?, occurredAt: String, hasRoute: Boolean, onSaved: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var reading by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<KmlRead.Problem?>(null) }
    var pending by remember { mutableStateOf<PendingRoute?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch {
            reading = true
            when (val read = KmlImport.read(context, uri)) {
                is KmlRead.Problem -> problem = read
                is KmlRead.Done -> {
                    val flight = read.flight
                    if (flight.track.size < 2) problem = KmlRead.Problem(R.string.kml_noroute_title, R.string.kml_not_message)
                    else pending = PendingRoute(flight.track, routeMessage(context, app, flight, originCode, destinationCode, occurredAt, hasRoute))
                }
            }
            reading = false
        }
    }
    OutlinedButton(onClick = { picker.launch(arrayOf("*/*")) }, enabled = !reading, modifier = Modifier.fillMaxWidth()) {
        Text(stringResource(if (reading) R.string.reading else if (hasRoute) R.string.route_replace else R.string.route_add))
    }
    pending?.let { route ->
        AlertDialog(
            onDismissRequest = { pending = null },
            title = { Text(stringResource(if (hasRoute) R.string.route_replace_title else R.string.route_save_title)) },
            text = { Text(route.message) },
            confirmButton = {
                TextButton(onClick = {
                    runCatching { app.tracks.save(route.track, flightId) }
                    pending = null
                    onSaved()
                }) { Text(stringResource(if (hasRoute) R.string.route_replace_button else R.string.route_save)) }
            },
            dismissButton = { TextButton(onClick = { pending = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }
    problem?.let { p ->
        AlertDialog(
            onDismissRequest = { problem = null },
            title = { Text(stringResource(p.title)) },
            text = { Text(stringResource(p.message)) },
            confirmButton = { TextButton(onClick = { problem = null }) { Text(stringResource(android.R.string.ok)) } },
        )
    }
}

/** What was found, and what does not fit this flight. Different airports or a different day are only a warning. */
private fun routeMessage(
    context: Context, app: WingspotApp, flight: KmlFlight, originCode: String?, destinationCode: String?, occurredAt: String, hasRoute: Boolean,
): String {
    val flown = app.prefs.unit.format(Math.round(FlightTrack.lengthKm(flight.track)).toInt())
    val lines = mutableListOf(context.getString(R.string.track_summary, flight.track.size, flown))
    val from = flight.origin?.iata
    val to = flight.destination?.iata
    if (from != null && to != null && originCode != null && destinationCode != null &&
        (!from.equals(originCode, ignoreCase = true) || !to.equals(destinationCode, ignoreCase = true))
    ) lines.add(context.getString(R.string.route_mismatch, from, to, originCode, destinationCode))
    val fileDay = flight.departureDate?.let { runCatching { java.time.LocalDate.parse(it).atStartOfDay(java.time.ZoneOffset.UTC).toInstant() }.getOrNull() }
    val flightTime = runCatching { java.time.OffsetDateTime.parse(occurredAt).toInstant() }.getOrNull()
    if (fileDay != null && flightTime != null && java.time.Duration.between(fileDay, flightTime).abs() > java.time.Duration.ofHours(36)) {
        lines.add(context.getString(R.string.route_other_day))
    }
    if (hasRoute) lines.add(context.getString(R.string.route_has_route))
    return lines.joinToString("\n\n")
}
