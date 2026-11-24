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
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.TextButton
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
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.text.font.FontFamily
import site.wingspot.core.MapsLink
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import site.wingspot.core.ApiException
import site.wingspot.core.SocialApi

/** The spotting locations of an airport, as a section of its page. Nothing is shown when there are none. */
@Composable
fun AirportSpotsSection(app: WingspotApp, model: SocialViewModel, airportId: Long) {
    var places by remember { mutableStateOf(emptyList<SocialApi.SpotLocation>()) }
    LaunchedEffect(airportId, model.spotsVersion) { places = try { app.social.spotLocations(airportId) } catch (e: ApiException) { emptyList() } }
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
        TextButton(onClick = { model.open(Route.AddSpot) }, modifier = Modifier.testTag("suggest-spot")) { Text(stringResource(R.string.suggest_place)) }
    }
}

/** Suggest a new spotting location. It waits for approval and only its author sees it until then. */
@Composable
fun AddSpotPage(app: WingspotApp, model: SocialViewModel) {
    var name by remember { mutableStateOf("") }
    var link by remember { mutableStateOf("") }
    var about by remember { mutableStateOf("") }
    var bestTime by remember { mutableStateOf("") }
    var facing by remember { mutableStateOf("") }
    var tips by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<Int?>(null) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var position by remember { mutableStateOf<Pair<Double, Double>?>(null) }
    LaunchedEffect(link) { position = if (link.isBlank()) null else MapsLink.resolve(link) }
    val canSend = name.trim().length >= 3 && position != null && !sending

    fun send() {
        val p = position ?: return
        sending = true
        scope.launch {
            fun optional(text: String) = text.trim().ifEmpty { null }
            val answer = try {
                app.social.addSpot(SocialApi.NewSpot(name.trim(), p.first, p.second, optional(about), optional(bestTime), optional(facing), optional(tips)))
            } catch (e: ApiException) { null }
            sending = false
            when {
                answer == null -> message = R.string.spot_send_failed
                answer.status == "pending" -> { model.spotAdded(); model.back() }
                answer.status == "duplicate" -> message = R.string.spot_duplicate
                else -> message = when (answer.code) {
                    "no_airport_nearby" -> R.string.spot_no_airport
                    "too_many_pending" -> R.string.spot_too_many
                    "invalid_name" -> R.string.spot_bad_name
                    else -> R.string.spot_not_added
                }
            }
        }
    }

    Column(Modifier.testTag("add-spot"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        PageHeader(stringResource(R.string.suggest_place), model::back)
        OutlinedTextField(name, { name = it }, singleLine = true, label = { Text(stringResource(R.string.spot_name_label)) }, modifier = Modifier.fillMaxWidth().testTag("spot-name"))
        OutlinedTextField(link, { link = it }, singleLine = true, label = { Text(stringResource(R.string.spot_link_label)) }, modifier = Modifier.fillMaxWidth().testTag("spot-link"))
        when {
            position != null -> Text(stringResource(R.string.spot_position, "%.5f, %.5f".format(position!!.first, position!!.second)), color = MaterialTheme.colorScheme.onSurfaceVariant)
            link.isNotBlank() -> Text(stringResource(R.string.spot_link_unclear), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(stringResource(R.string.spot_where_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        OutlinedTextField(about, { about = it }, label = { Text(stringResource(R.string.spot_about)) }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(bestTime, { bestTime = it }, singleLine = true, label = { Text(stringResource(R.string.spot_best_time)) }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(facing, { facing = it }, singleLine = true, label = { Text(stringResource(R.string.spot_facing)) }, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(tips, { tips = it }, label = { Text(stringResource(R.string.spot_tips)) }, modifier = Modifier.fillMaxWidth())
        message?.let { Text(stringResource(it), color = MaterialTheme.colorScheme.error) }
        Button(onClick = ::send, enabled = canSend, modifier = Modifier.fillMaxWidth().testTag("spot-send")) { Text(stringResource(R.string.suggest_this_place)) }
        Text(stringResource(R.string.spot_review_note), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** One spotting location: where it is, what to know before going, and how much it is used. */
@Composable
fun SpotPage(app: WingspotApp, model: SocialViewModel, id: Long) {
    var detail by remember { mutableStateOf<SocialApi.SpotDetail?>(null) }
    var loaded by remember { mutableStateOf(false) }
    var aircraft by remember { mutableStateOf(emptyList<SocialApi.SpotSighting>()) }
    var hasMore by remember { mutableStateOf(false) }
    var loadingMore by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    /** The next 20 aircraft spotted here, after the last one shown. */
    suspend fun loadMore() {
        loadingMore = true
        val last = aircraft.lastOrNull()
        runCatching { app.social.spotSightings(id, 20, last?.occurredAt, last?.id) }.onSuccess { page ->
            aircraft = aircraft + page
            hasMore = page.size == 20
        }
        loadingMore = false
    }
    LaunchedEffect(id) {
        detail = try { app.social.spotDetail(id) } catch (e: ApiException) { null }
        loaded = true
        if (detail != null) loadMore()
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
                if (aircraft.isNotEmpty()) {
                    Text(stringResource(R.string.spot_aircraft_here), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 8.dp))
                    for (sighting in aircraft) {
                        Column(Modifier.fillMaxWidth().clickable { model.open(Route.CheckInPage(sighting.id)) }.padding(vertical = 6.dp).testTag("spot-aircraft-${sighting.id}")) {
                            Text(sighting.title, fontFamily = FontFamily.Monospace)
                            Text("${sighting.person} · ${sighting.occurredAt.take(10)}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    if (hasMore) TextButton(onClick = { scope.launch { loadMore() } }, enabled = !loadingMore, modifier = Modifier.testTag("spot-show-more")) { Text(stringResource(R.string.show_more)) }
                }
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

private val staffLabels = mutableMapOf<String, String?>()

/** The small mark next to a name for people with a role label (the founder). */
@Composable
fun StaffLabel(app: WingspotApp, user: String) {
    var label by remember(user) { mutableStateOf(staffLabels[user]) }
    LaunchedEffect(user) {
        if (!staffLabels.containsKey(user)) {
            try { staffLabels[user] = app.social.staffLabel(user); label = staffLabels[user] } catch (e: ApiException) { }
        }
    }
    if (label == "founder") {
        // A small pill: the star sits right next to the word, on a soft tint, so it reads as a badge.
        androidx.compose.material3.Surface(
            shape = androidx.compose.foundation.shape.RoundedCornerShape(50),
            color = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f),
            modifier = Modifier.padding(top = 4.dp).testTag("staff-label"),
        ) {
            Text(
                "★ " + stringResource(R.string.founder_label), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
            )
        }
    }
}

/** The places that wait for a decision. Shown to people with the review permission. */
@Composable
fun ReviewSpotsPage(app: WingspotApp, model: SocialViewModel) {
    var places by remember { mutableStateOf<List<SocialApi.PendingSpot>?>(null) }
    var rejecting by remember { mutableStateOf<SocialApi.PendingSpot?>(null) }
    var note by remember { mutableStateOf("") }
    var message by remember { mutableStateOf<Int?>(null) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val uriHandler = LocalUriHandler.current
    LaunchedEffect(Unit) { places = try { app.social.pendingSpots() } catch (e: ApiException) { emptyList() } }

    fun decide(place: SocialApi.PendingSpot, approve: Boolean, text: String?) {
        scope.launch {
            val answer = try { app.social.reviewSpot(place.id, approve, text) } catch (e: ApiException) { null }
            when {
                answer != null && answer.code == null -> places = places?.filter { it.id != place.id }
                answer?.code == "not_pending" -> { message = R.string.review_taken; places = places?.filter { it.id != place.id } }
                else -> message = R.string.review_failed
            }
        }
    }

    Column(Modifier.fillMaxWidth().testTag("review-spots"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            TextButton(onClick = model::back) { Text("‹ " + stringResource(R.string.back)) }
            Text(stringResource(R.string.review_places), style = MaterialTheme.typography.titleLarge)
        }
        val list = places
        when {
            list == null -> CircularProgressIndicator(Modifier.padding(16.dp))
            list.isEmpty() -> Text(stringResource(R.string.review_nothing), color = MaterialTheme.colorScheme.onSurfaceVariant)
            else -> list.forEach { place ->
                Column(Modifier.fillMaxWidth().testTag("review-row"), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(place.name, style = MaterialTheme.typography.titleMedium)
                    Text("${place.airportCode} · ${place.airportName}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    (place.authorName ?: place.authorUsername)?.let {
                        Text(stringResource(R.string.review_suggested_by, it), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    listOfNotNull(place.description, place.bestTime, place.facing, place.tips, place.legalNotes).forEach {
                        Text(it, style = MaterialTheme.typography.bodySmall)
                    }
                    TextButton(onClick = {
                        runCatching { uriHandler.openUri("https://www.google.com/maps/search/?api=1&query=${place.latitude},${place.longitude}") }
                    }) { Text(stringResource(R.string.open_in_maps)) }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { decide(place, true, null) }, modifier = Modifier.testTag("review-approve")) { Text(stringResource(R.string.review_approve)) }
                        OutlinedButton(onClick = { note = ""; rejecting = place }, modifier = Modifier.testTag("review-reject")) { Text(stringResource(R.string.review_reject)) }
                    }
                    HorizontalDivider(Modifier.padding(top = 8.dp))
                }
            }
        }
    }
    rejecting?.let { place ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { rejecting = null },
            title = { Text(stringResource(R.string.review_reject_title)) },
            text = { OutlinedTextField(note, { note = it }, label = { Text(stringResource(R.string.review_reason)) }, modifier = Modifier.testTag("review-reason")) },
            confirmButton = { TextButton(onClick = { rejecting = null; decide(place, false, note) }, modifier = Modifier.testTag("review-confirm-reject")) { Text(stringResource(R.string.review_reject)) } },
            dismissButton = { TextButton(onClick = { rejecting = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }
    message?.let {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { message = null },
            text = { Text(stringResource(it)) },
            confirmButton = { TextButton(onClick = { message = null }) { Text(stringResource(R.string.ok)) } },
        )
    }
}
