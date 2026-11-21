package site.wingspot.app

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import site.wingspot.core.ApiException
import site.wingspot.core.SocialApi

/** The spotting locations of an airport, as a section of its page. Nothing is shown when there are none. */
@Composable
fun AirportSpotsSection(app: WingspotApp, model: SocialViewModel, airportId: Long) {
    var places by remember { mutableStateOf(emptyList<SocialApi.SpotLocation>()) }
    LaunchedEffect(airportId) { places = try { app.social.spotLocations(airportId) } catch (e: ApiException) { emptyList() } }
    if (places.isEmpty()) return
    Column(Modifier.testTag("airport-spots"), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        SectionHeader(stringResource(R.string.spotting_locations), Modifier.padding(top = 8.dp))
        places.forEach { place ->
            Column(Modifier.fillMaxWidth().clickable { model.open(Route.SpotPage(place.id)) }.padding(vertical = 8.dp)) {
                Text(place.name, style = MaterialTheme.typography.bodyLarge)
                if (place.isPending) {
                    Text(stringResource(R.string.spot_pending_short), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else if (place.sessions > 0) {
                    Text(stringResource(R.string.spot_sessions_count, place.sessions), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            HorizontalDivider()
        }
    }
}

/** One spotting location: where it is, what to know before going, and how much it is used. */
@Composable
fun SpotPage(app: WingspotApp, model: SocialViewModel, id: Long) {
    var detail by remember { mutableStateOf<SocialApi.SpotDetail?>(null) }
    var loaded by remember { mutableStateOf(false) }
    LaunchedEffect(id) {
        detail = try { app.social.spotDetail(id) } catch (e: ApiException) { null }
        loaded = true
    }
    val uriHandler = LocalUriHandler.current
    Column(Modifier.testTag("spot-page"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        PageHeader(detail?.name.orEmpty(), model::back)
        val place = detail
        when {
            place != null -> {
                Text(place.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text(listOfNotNull(place.iata, place.airport).joinToString(" · "), color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (place.isPending) Text(stringResource(R.string.spot_pending), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                OutlinedButton(onClick = {
                    runCatching { uriHandler.openUri("https://www.google.com/maps/search/?api=1&query=${place.latitude},${place.longitude}") }
                }, modifier = Modifier.testTag("open-in-maps")) { Text(stringResource(R.string.open_in_maps)) }
                CountRow(R.string.spot_sessions, place.sessions)
                CountRow(R.string.spot_aircraft_seen, place.aircraft)
                CountRow(R.string.spot_your_sessions, place.mySessions)
                Text(stringResource(R.string.spot_counts_note), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                listOf(
                    R.string.spot_about to place.description, R.string.spot_best_time to place.bestTime, R.string.spot_facing to place.facing,
                    R.string.spot_tips to place.tips, R.string.spot_good_to_know to place.legalNotes,
                ).forEach { (label, text) ->
                    if (!text.isNullOrBlank()) {
                        Column(Modifier.padding(top = 8.dp)) {
                            Text(stringResource(label), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(text)
                        }
                    }
                }
            }
            !loaded -> CircularProgressIndicator(Modifier.padding(16.dp))
            else -> Text(stringResource(R.string.spot_unavailable), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun CountRow(label: Int, value: Int) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
        Text(stringResource(label), Modifier.weight(1f))
        Text(value.toString())
    }
}

/** On a check-in page: the place of a session, and the aircraft seen during it. */
@Composable
fun CheckInSpotSection(app: WingspotApp, model: SocialViewModel, checkInId: String, kind: String) {
    var spot by remember { mutableStateOf<SocialApi.CheckInSpot?>(null) }
    var sightings by remember { mutableStateOf(emptyList<SocialApi.VisitSighting>()) }
    LaunchedEffect(checkInId) {
        spot = try { app.social.checkInSpot(checkInId) } catch (e: ApiException) { null }
        val visit = spot?.visitId
        if (kind == "airport" && visit != null) sightings = try { app.social.visitSightings(visit) } catch (e: ApiException) { emptyList() }
    }
    val current = spot ?: return
    Column(Modifier.testTag("checkin-spot"), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        val name = current.spotName
        val spotId = current.spotId
        if (name != null && spotId != null) {
            Text(
                stringResource(if (kind == "airport") R.string.spot_at else R.string.spot_spotted_at, name),
                style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.fillMaxWidth().clickable { model.open(Route.SpotPage(spotId)) }.padding(vertical = 8.dp),
            )
        }
        if (kind == "airport" && sightings.isNotEmpty()) {
            Text(stringResource(R.string.spot_aircraft_seen), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            val time = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)
            sightings.forEach { s ->
                Row(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                    Text(listOfNotNull(s.registration, s.typeIcao).joinToString(" · "), Modifier.weight(1f))
                    Text(runCatching { time.format(Instant.parse(s.occurredAt).atZone(ZoneId.systemDefault())) }.getOrDefault(""), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}
