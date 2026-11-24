package site.wingspot.app

import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.UUID
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import site.wingspot.core.AircraftType
import site.wingspot.core.Airport
import site.wingspot.core.BoardingPass
import site.wingspot.core.CabinClass
import site.wingspot.core.CheckInStore
import site.wingspot.core.FeedPhoto
import site.wingspot.core.FlightTrack
import site.wingspot.core.GeoCoordinate
import site.wingspot.core.GreatCircle
import site.wingspot.core.KmlFlight
import site.wingspot.core.LocalCheckIn
import site.wingspot.core.RecentTypes
import site.wingspot.core.Registration
import site.wingspot.core.SocialApi
import site.wingspot.core.SpotChange
import site.wingspot.core.SyncState
import site.wingspot.core.VisitContext
import site.wingspot.core.WhenChoice
import site.wingspot.core.departureDay

/** A check-in: Spotted, Airport or Flown. Saved on the phone first. */
@Composable
fun CheckInScreen(state: CheckInState, reference: ReferenceState, model: CheckInViewModel) {
    val result = state.result
    if (result != null) {
        ResultView(result, onReturn = if (state.afterFlight != null) model::returnFromResult else null, onAnother = model::another, onDone = model::close)
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        state.session?.takeIf { it.isActive(java.time.Instant.now()) }?.let { session ->
            Row(Modifier.fillMaxWidth().testTag("spot-session"), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.session_at, session.spotName), style = MaterialTheme.typography.titleSmall)
                    Text(stringResource(R.string.session_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                TextButton(onClick = model::endSession) { Text(stringResource(R.string.end_session)) }
            }
        }
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for ((kind, label) in listOf(Kind.SPOTTED to R.string.spotted_title, Kind.AIRPORT to R.string.airport_title, Kind.FLOWN to R.string.flown_title)) {
                FilterChip(selected = state.kind == kind, onClick = { model.chooseKind(kind) }, label = { Text(stringResource(label)) }, modifier = Modifier.testTag("kind-$kind"))
            }
        }
        when (state.kind) {
            Kind.SPOTTED -> SpottedForm(state, reference, model)
            Kind.AIRPORT -> AirportForm(state, reference, model)
            Kind.FLOWN -> FlownForm(state, reference, model)
        }
    }
}

@Composable
private fun SpottedForm(state: CheckInState, reference: ReferenceState, model: CheckInViewModel) {
    var input by rememberSaveable { mutableStateOf("") }
    var type by remember { mutableStateOf<AircraftType?>(null) }
    var airport by remember { mutableStateOf<Airport?>(null) }
    var photos by remember { mutableStateOf(emptyList<PreparedPhoto>()) }
    var spot by remember { mutableStateOf<SocialApi.SpotLocation?>(null) }
    val registration = Registration.parse(input)
    val canSave = if (input.isNotBlank()) registration != null else type != null
    // During a session the airport is the session's.
    val session = state.session
    // During a session at a backdated visit, the sighting starts with the visit's date and time.
    val visitChoice = session?.visitMoment?.let { WhenChoice.existing(it, session.visitTimeKnown) }
    var whenChoice by remember(session?.visitId) { mutableStateOf(visitChoice ?: WhenChoice.NOW) }
    LaunchedEffect(session?.airportId, reference.database) {
        if (airport == null && session != null) airport = reference.database?.airport(session.airportId)
    }

    Text(stringResource(R.string.spotted_title), style = MaterialTheme.typography.titleLarge)
    OutlinedTextField(
        value = input, onValueChange = { input = it }, singleLine = true,
        label = { Text(stringResource(R.string.registration_label)) }, modifier = Modifier.fillMaxWidth().testTag("registration"),
    )
    RegistrationHint(input, registration, orType = true)
    if (registration == null) TypePicker(reference, type) { type = it }
    AirportPicker(stringResource(R.string.airport_label), reference, airport) { airport = it }
    SightingSpotField(airport?.id, inSession = session != null, spot = spot, onSpot = { spot = it })
    WhenField(whenChoice, { whenChoice = it }, photos, visitChoice)
    PhotoField(photos) { photos = it }
    SaveBar(state, enabled = canSave, onSave = { model.save(registration, type, airport, photos, spot, whenChoice.moment()) }, onCancel = model::close)
}

/**
 * The spotting place of a sighting: chips with the places of the sighting's airport, "None" by default. Not shown without an airport,
 * with no place there, or during a session (the session has the place). [onLoaded] says whether the places were read, so an edit knows
 * "None" was a real choice and not a failed request.
 */
@Composable
internal fun SightingSpotField(
    airportId: Long?, inSession: Boolean, spot: SocialApi.SpotLocation?, onSpot: (SocialApi.SpotLocation?) -> Unit, onLoaded: (Boolean) -> Unit = {},
) {
    val app = LocalContext.current.applicationContext as WingspotApp
    var places by remember { mutableStateOf(emptyList<SocialApi.SpotLocation>()) }
    LaunchedEffect(airportId) {
        val found = airportId?.let { runCatching { app.social.spotLocations(it) }.getOrDefault(emptyList()) } ?: emptyList()
        places = found
        // An empty answer may be a failed request: then nothing is decided, and an edit leaves the place as it was.
        onLoaded(found.isNotEmpty())
        if (found.isNotEmpty() && spot != null && found.none { it.id == spot.id }) onSpot(null)
    }
    if (inSession || places.isEmpty()) return
    Text(stringResource(R.string.spotting_location_label), style = MaterialTheme.typography.labelLarge)
    Row(Modifier.horizontalScroll(rememberScrollState()).testTag("sighting-spot-choices"), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        FilterChip(selected = spot == null, onClick = { onSpot(null) }, label = { Text(stringResource(R.string.spot_none)) })
        for (place in places) FilterChip(selected = spot?.id == place.id, onClick = { onSpot(place) }, label = { Text(place.name) })
    }
}

@Composable
private fun AirportForm(state: CheckInState, reference: ReferenceState, model: CheckInViewModel) {
    var airport by remember { mutableStateOf<Airport?>(null) }
    var context by rememberSaveable { mutableStateOf(VisitContext.SPOTTING) }
    var photos by remember { mutableStateOf(emptyList<PreparedPhoto>()) }
    val tags = rememberTagChoice()
    val app = LocalContext.current.applicationContext as WingspotApp
    var places by remember { mutableStateOf(emptyList<SocialApi.SpotLocation>()) }
    var spot by remember { mutableStateOf<SocialApi.SpotLocation?>(null) }
    var whenChoice by remember { mutableStateOf(WhenChoice.NOW) }
    LaunchedEffect(airport?.id) {
        spot = null
        places = airport?.let { a -> runCatching { app.social.spotLocations(a.id) }.getOrDefault(emptyList()) } ?: emptyList()
    }
    Text(stringResource(R.string.airport_title), style = MaterialTheme.typography.titleLarge)
    AirportPicker(stringResource(R.string.airport_label), reference, airport) { airport = it }
    if (places.isNotEmpty()) {
        Text(stringResource(R.string.spotting_location_label), style = MaterialTheme.typography.labelLarge)
        Row(Modifier.horizontalScroll(rememberScrollState()).testTag("spot-choices"), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(selected = spot == null, onClick = { spot = null }, label = { Text(stringResource(R.string.spot_none)) })
            for (place in places) FilterChip(selected = spot?.id == place.id, onClick = { spot = place }, label = { Text(place.name) })
        }
    }
    Text(stringResource(R.string.why_there), style = MaterialTheme.typography.labelLarge)
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for (option in VisitContext.entries) {
            FilterChip(selected = context == option, onClick = { context = option }, label = { Text(stringResource(visitTitle(option))) })
        }
    }
    WithFriendsField(tags)
    WhenField(whenChoice, { whenChoice = it }, photos)
    PhotoField(photos) { photos = it }
    SaveBar(
        state, enabled = airport != null,
        onSave = { model.saveAirport(airport!!, context, photos, tags.all(), spot, if (whenChoice.isNow) null else whenChoice.moment()) },
        onCancel = model::close,
    )
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun FlownForm(state: CheckInState, reference: ReferenceState, model: CheckInViewModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // For a return flight the form starts with the route the other way round, the same day, and the cabin and friends of the flight before.
    val start = state.returnStart
    var origin by remember(start) { mutableStateOf<Airport?>(start?.origin) }
    var destination by remember(start) { mutableStateOf<Airport?>(start?.destination) }
    var flightNumber by rememberSaveable(start) { mutableStateOf("") }
    var input by rememberSaveable(start) { mutableStateOf("") }
    var type by remember(start) { mutableStateOf<AircraftType?>(null) }
    var cabin by rememberSaveable(start) { mutableStateOf<CabinClass?>(start?.cabin) }
    var seat by rememberSaveable(start) { mutableStateOf("") }
    var photos by remember(start) { mutableStateOf(emptyList<PreparedPhoto>()) }
    val tags = rememberTagChoice()
    LaunchedEffect(start) { if (start != null) tags.chosen = start.tagged }
    var date by rememberSaveable(start) { mutableStateOf((start?.date ?: LocalDate.now()).toString()) }
    var pickDate by remember { mutableStateOf(false) }
    var scanning by remember { mutableStateOf(false) }
    var reading by remember { mutableStateOf(false) }
    var choices by remember { mutableStateOf(emptyList<BoardingPass.Leg>()) }
    var problem by remember { mutableStateOf<Int?>(null) }
    var missing by remember { mutableStateOf("") }
    // A KML file of a flight: what it filled in, which fields it did not have, and the route, which stays on this phone.
    var importing by remember { mutableStateOf(false) }
    var importedTrack by remember(start) { mutableStateOf(emptyList<GeoCoordinate>()) }
    var notice by remember(start) { mutableStateOf<Pair<List<Int>, List<Int>>?>(null) }
    var kmlProblem by remember { mutableStateOf<KmlRead.Problem?>(null) }
    val unit = (context.applicationContext as WingspotApp).prefs.unit
    val registration = Registration.parse(input)
    val sameAirport = origin != null && origin?.id == destination?.id
    val canSave = origin != null && destination != null && !sameAirport && (input.isBlank() || registration != null)
    val day = LocalDate.parse(date)
    val normalizedNumber = flightNumber.filterNot { it.isWhitespace() }.uppercase()
    val duplicate = normalizedNumber.isNotEmpty() && state.all.any {
        it.kind == "flown" && it.flightNumber == normalizedNumber && it.occurredAt.atZone(ZoneId.systemDefault()).toLocalDate() == day
    }

    /** Fills the form from one flight on the pass. The cabin stays as it is, because the booking class letter means different things at different airlines. */
    fun apply(leg: BoardingPass.Leg) {
        val db = reference.database
        if (db == null) { problem = R.string.scan_needs_data; return }
        scope.launch {
            val from = db.airport(leg.from)
            val to = db.airport(leg.to)
            if (from == null || to == null) {
                missing = listOfNotNull(if (from == null) leg.from else null, if (to == null) leg.to else null).joinToString(", ")
                problem = R.string.scan_airports_unknown
                return@launch
            }
            origin = from; destination = to
            flightNumber = leg.carrier + leg.flightNumber
            seat = leg.seat.orEmpty()
            leg.flightDate(LocalDate.now())?.let { date = minOf(it, LocalDate.now()).toString() }
        }
    }
    fun handle(pass: BoardingPass) {
        if (pass.legs.size == 1) apply(pass.legs.first()) else choices = pass.legs
    }

    /** Fills the form from a KML file. A field the file doesn't have stays as it is, and the notice says which. */
    fun applyImport(flight: KmlFlight) {
        scope.launch {
            val found = mutableListOf<Int>()
            val db = reference.database
            if (db != null) {
                val from = flight.origin?.iata?.let { db.airport(it) }
                val to = flight.destination?.iata?.let { db.airport(it) }
                if (from != null && to != null && from.id != to.id) { origin = from; destination = to; found += R.string.field_route }
                flight.aircraftTypeCode?.let { db.aircraftType(it) }?.let { type = it; found += R.string.field_type }
            }
            flight.departureDay()?.let { date = it.toString(); found += R.string.field_date }
            flight.flightNumber?.let { flightNumber = it; found += R.string.field_flight_number }
            flight.registration?.takeIf { Registration.parse(it) != null }?.let { input = it; found += R.string.field_registration }
            importedTrack = if (flight.track.size >= 2) flight.track else emptyList()
            val all = listOf(R.string.field_route, R.string.field_date, R.string.field_flight_number, R.string.field_registration, R.string.field_type)
            notice = found to all.filterNot { it in found }
        }
    }

    if (scanning) {
        BoardingPassScanner(onPass = { scanning = false; handle(it) }, onClose = { scanning = false })
        return
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            reading = true
            val pass = boardingPassInImage(context, uri)
            reading = false
            if (pass == null) problem = R.string.scan_none_found else handle(pass)
        }
    }

    val importPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch {
            importing = true
            when (val read = KmlImport.read(context, uri)) {
                is KmlRead.Problem -> kmlProblem = read
                is KmlRead.Done -> applyImport(read.flight)
            }
            importing = false
        }
    }

    Text(stringResource(R.string.flown_title), style = MaterialTheme.typography.titleLarge)
    OutlinedButton(onClick = { scanning = true }, modifier = Modifier.fillMaxWidth().testTag("scan-pass")) { Text(stringResource(R.string.scan_boarding_pass)) }
    OutlinedButton(
        onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, enabled = !reading,
        modifier = Modifier.fillMaxWidth(),
    ) { Text(stringResource(if (reading) R.string.reading else R.string.read_from_picture)) }
    // The server can switch the import off (docs/KML-IMPORT-PLAN.md).
    val kmlImportOn = (context.applicationContext as WingspotApp).prefs.kmlImportOn
    if (kmlImportOn) OutlinedButton(
        onClick = { importPicker.launch(arrayOf("*/*")) }, enabled = !importing,
        modifier = Modifier.fillMaxWidth().testTag("import-kml"),
    ) { Text(stringResource(if (importing) R.string.reading else R.string.import_kml)) }
    Text(stringResource(R.string.scan_footer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    if (kmlImportOn) Text(stringResource(R.string.import_footer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    notice?.let { (found, missing) ->
        HorizontalDivider()
        Text(stringResource(R.string.imported_title), style = MaterialTheme.typography.titleMedium)
        if (found.isNotEmpty()) Text(stringResource(R.string.imported_found, found.map { stringResource(it) }.joinToString(", ")), modifier = Modifier.testTag("import-found"))
        if (missing.isNotEmpty()) Text(stringResource(R.string.imported_missing, missing.map { stringResource(it) }.joinToString(", ")))
        if (importedTrack.size >= 2) {
            val flown = FlightTrack.lengthKm(importedTrack)
            val direct = if (origin != null && destination != null && !sameAirport) {
                GreatCircle.distanceKm(site.wingspot.core.GeoCoordinate(origin!!.latitude, origin!!.longitude), site.wingspot.core.GeoCoordinate(destination!!.latitude, destination!!.longitude))
            } else null
            val detour = direct?.let { FlightTrack.detour(flown, it) }
            Text(
                if (detour != null && detour.extraKm >= 1) {
                    stringResource(R.string.track_summary_detour, importedTrack.size, unit.format(Math.round(flown).toInt()), unit.format(Math.round(detour.extraKm).toInt()), Math.round(detour.percent).toInt())
                } else {
                    stringResource(R.string.track_summary, importedTrack.size, unit.format(Math.round(flown).toInt()))
                },
                modifier = Modifier.testTag("import-track"),
            )
        }
        if (duplicate) Text(stringResource(R.string.imported_duplicate, normalizedNumber), color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("import-duplicate"))
        Text(stringResource(R.string.imported_check), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        HorizontalDivider()
    }
    AirportPicker(stringResource(R.string.from_label), reference, origin) { origin = it }
    AirportPicker(stringResource(R.string.to_label), reference, destination) { destination = it }
    if (sameAirport) Text(stringResource(R.string.same_airport), color = MaterialTheme.colorScheme.error)
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        Text(stringResource(R.string.date_label))
        TextButton(onClick = { pickDate = true }, modifier = Modifier.testTag("flight-date")) { Text(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(day)) }
    }
    FlightDetails(
        flightNumber, { flightNumber = it }, input, { input = it }, registration, reference, type, { type = it }, cabin, { cabin = it }, seat, { seat = it },
        recentTypes = RecentTypes.forFlight(state.all, flightNumber),
    )
    WithFriendsField(tags)
    PhotoField(photos) { photos = it }
    SaveBar(
        state, enabled = canSave,
        onSave = {
            // A flight has a day but no time here. Today keeps the real time; any other day uses midday, which stays on that day.
            val at = if (day == LocalDate.now()) java.time.Instant.now() else day.atTime(12, 0).atZone(ZoneId.systemDefault()).toInstant()
            model.saveFlight(
                origin!!, destination!!, flightNumber, registration, type, cabin, seat, photos, at, tags.all(),
                returnTo = ReturnStart(destination!!, origin!!, day, cabin, tags.chosen), track = importedTrack,
            )
        },
        onCancel = model::close,
    )

    if (pickDate) FlightDatePicker(day, onPick = { date = it.toString(); pickDate = false }, onDismiss = { pickDate = false })
    if (choices.isNotEmpty()) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { choices = emptyList() },
            title = { Text(stringResource(R.string.which_flight)) },
            text = {
                Column {
                    choices.forEach { leg ->
                        TextButton(onClick = { choices = emptyList(); apply(leg) }, modifier = Modifier.fillMaxWidth()) { Text("${leg.from} → ${leg.to} · ${leg.carrier}${leg.flightNumber}") }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { choices = emptyList() }) { Text(stringResource(R.string.cancel)) } },
        )
    }
    kmlProblem?.let { read ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { kmlProblem = null },
            title = { Text(stringResource(read.title)) },
            text = { Text(stringResource(read.message)) },
            confirmButton = { TextButton(onClick = { kmlProblem = null }) { Text(stringResource(R.string.ok)) } },
        )
    }
    problem?.let { res ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { problem = null },
            title = { Text(stringResource(if (res == R.string.scan_none_found) R.string.scan_none_title else R.string.scan_problem_title)) },
            text = { Text(if (res == R.string.scan_airports_unknown) stringResource(res, missing) else stringResource(res)) },
            confirmButton = { TextButton(onClick = { problem = null }) { Text(stringResource(R.string.ok)) } },
        )
    }
}

/** The day of a flight, chosen on a calendar. Days after today can't be chosen. */
@Composable
internal fun FlightDatePicker(day: LocalDate, onPick: (LocalDate) -> Unit, onDismiss: () -> Unit) {
    val startMillis = day.atStartOfDay(java.time.ZoneOffset.UTC).toInstant().toEpochMilli()
    val pickerState = androidx.compose.material3.rememberDatePickerState(
        initialSelectedDateMillis = startMillis,
        selectableDates = object : androidx.compose.material3.SelectableDates {
            override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis <= LocalDate.now().plusDays(1).atStartOfDay(java.time.ZoneOffset.UTC).toInstant().toEpochMilli()
        },
    )
    androidx.compose.material3.DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = {
                pickerState.selectedDateMillis?.let { onPick(minOf(java.time.Instant.ofEpochMilli(it).atZone(java.time.ZoneOffset.UTC).toLocalDate(), LocalDate.now())) } ?: onDismiss()
            }) { Text(stringResource(R.string.done)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    ) { androidx.compose.material3.DatePicker(state = pickerState) }
}

/** Fills in or corrects the details of a saved flight. The route and the photos stay as they were. */
@Composable
fun FlownEditScreen(
    flight: LocalCheckIn, state: CheckInState, reference: ReferenceState, model: CheckInViewModel,
    existing: List<FeedPhoto> = emptyList(), onDeletePhoto: suspend (FeedPhoto) -> Boolean = { true },
) {
    // Photos the check-in already has that were marked as removed: they are deleted when this screen is saved, and Cancel keeps them.
    var removed by remember { mutableStateOf(emptySet<String>()) }
    var deleteFailed by remember { mutableStateOf(false) }
    val saveScope = rememberCoroutineScope()
    var flightNumber by rememberSaveable { mutableStateOf(flight.flightNumber.orEmpty()) }
    var input by rememberSaveable { mutableStateOf(flight.registration.orEmpty()) }
    var type by remember { mutableStateOf<AircraftType?>(null) }
    var cabin by rememberSaveable { mutableStateOf(CabinClass.fromWire(flight.cabin)) }
    var seat by rememberSaveable { mutableStateOf(flight.seat.orEmpty()) }
    val originalDay = remember { flight.occurredAt.atZone(ZoneId.systemDefault()).toLocalDate() }
    var day by rememberSaveable { mutableStateOf(originalDay.toString()) }
    var pickDate by remember { mutableStateOf(false) }
    val chosenDay = LocalDate.parse(day)
    val registration = Registration.parse(input)
    // The type this flight already has stays until another is chosen.
    val keptType = flight.typeIcao.takeIf { type == null }
    var photos by remember { mutableStateOf(emptyList<PreparedPhoto>()) }
    val tags = rememberTagChoice(flight.id)

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.edit_flight), style = MaterialTheme.typography.titleLarge)
        Text(flight.title, style = MaterialTheme.typography.titleLarge, fontFamily = FontFamily.Monospace)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            Text(stringResource(R.string.date_label))
            TextButton(onClick = { pickDate = true }, modifier = Modifier.testTag("flight-date")) { Text(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(chosenDay)) }
        }
        if (pickDate) FlightDatePicker(chosenDay, onPick = { day = it.toString(); pickDate = false }, onDismiss = { pickDate = false })
        FlightDetails(
            flightNumber, { flightNumber = it }, input, { input = it }, registration, reference, type, { type = it }, cabin, { cabin = it }, seat, { seat = it },
            keptType = keptType, recentTypes = RecentTypes.forFlight(state.all, flightNumber, flight.id),
        )
        WithFriendsField(tags)
        // The server's photos count too: a check-in restored on a new phone has none of its own copies here. A photo marked as
        // removed makes room for one more.
        val room = minOf(state.roomForPhotos, CheckInStore.MAX_PHOTOS - existing.size).coerceAtLeast(0) + removed.size
        if (room > 0 || existing.isNotEmpty()) PhotoField(photos, room, existing, removed, { removed = removed + it.id }) { photos = it }
        if (deleteFailed) Text(stringResource(R.string.delete_photo_failed), color = MaterialTheme.colorScheme.error)
        VisibilityRow(androidx.compose.ui.platform.LocalContext.current.applicationContext as WingspotApp, flight.id.toString())
        SaveBar(
            state, enabled = input.isBlank() || registration != null,
            onSave = {
                // The time stays as it was unless another day is chosen. Today keeps the real time, any other day uses midday.
                val at = if (chosenDay == originalDay) null
                else if (chosenDay == LocalDate.now()) java.time.Instant.now()
                else chosenDay.atTime(12, 0).atZone(ZoneId.systemDefault()).toInstant()
                saveScope.launch {
                    deleteFailed = !deleteRemoved(existing, removed, onDeletePhoto) { removed = it }
                    if (!deleteFailed) model.saveEdit(flight.id, registration, type, keptType, flightNumber, cabin, seat, at, photos, tags.ifChanged())
                }
            },
            onCancel = model::cancelEdit,
        )
    }
}

/** Corrects a sighting (the aircraft) or an airport visit (the reason), adds a photo, and says who can see it. Flights have [FlownEditScreen]. */
@Composable
fun SimpleEditScreen(
    app: WingspotApp, checkIn: LocalCheckIn, state: CheckInState, reference: ReferenceState, model: CheckInViewModel,
    existing: List<FeedPhoto> = emptyList(), onDeletePhoto: suspend (FeedPhoto) -> Boolean = { true },
) {
    val isVisit = checkIn.kind == "airport"
    var removed by remember { mutableStateOf(emptySet<String>()) }
    var deleteFailed by remember { mutableStateOf(false) }
    val saveScope = rememberCoroutineScope()
    var input by rememberSaveable { mutableStateOf(checkIn.registration.orEmpty()) }
    var type by remember { mutableStateOf<AircraftType?>(null) }
    var reason by rememberSaveable { mutableStateOf(VisitContext.entries.firstOrNull { it.wire == checkIn.visitContext } ?: VisitContext.SPOTTING) }
    val registration = Registration.parse(input)
    // The type this sighting already has stays until another is chosen.
    val keptType = checkIn.typeIcao.takeIf { type == null }
    val hasAircraft = (registration != null && input.isNotBlank()) || type != null || keptType != null
    var photos by remember { mutableStateOf(emptyList<PreparedPhoto>()) }
    val tags = rememberTagChoice(checkIn.id)
    // A sighting's spotting place, and whether the places of its airport were read (so "None" is a real choice).
    var spot by remember { mutableStateOf(checkIn.spotId?.let { SocialApi.SpotLocation(it, checkIn.spotName.orEmpty(), 0.0, 0.0, null, "approved", false, 0) }) }
    var spotsLoaded by remember { mutableStateOf(false) }
    val inSession = checkIn.visitId != null
    // When it happened. A visit of a flight follows its flight, so it has no field.
    val followsFlight = checkIn.flightId != null
    val originalWhen = remember(checkIn.id) { WhenChoice.existing(checkIn.occurredAt, checkIn.timeKnown) }
    var whenChoice by remember(checkIn.id) { mutableStateOf(originalWhen) }
    val newMoment = if (followsFlight || whenChoice == originalWhen) null else whenChoice.moment()
    val spotChange = when {
        !spotsLoaded || inSession -> SpotChange.Keep
        spot != null -> if (spot!!.id == checkIn.spotId) SpotChange.Keep else SpotChange.Set(spot!!.id, spot!!.name)
        else -> if (checkIn.spotId == null) SpotChange.Keep else SpotChange.Clear
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(if (isVisit) R.string.edit_visit else R.string.edit_sighting), style = MaterialTheme.typography.titleLarge)
        Text(checkIn.title, style = MaterialTheme.typography.titleLarge, fontFamily = FontFamily.Monospace)
        if (isVisit) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (option in VisitContext.entries) {
                    FilterChip(selected = reason == option, onClick = { reason = option }, label = { Text(stringResource(visitTitle(option))) })
                }
            }
        } else {
            OutlinedTextField(
                value = input, onValueChange = { input = it }, singleLine = true,
                label = { Text(stringResource(R.string.registration_label)) }, modifier = Modifier.fillMaxWidth(),
            )
            RegistrationHint(input, registration, orType = false)
            if (keptType != null) Text(stringResource(R.string.type_kept, keptType), style = MaterialTheme.typography.bodySmall)
            TypePicker(reference, type) { type = it }
            SightingSpotField(checkIn.airportId, inSession = inSession, spot = spot, onSpot = { spot = it }, onLoaded = { spotsLoaded = it })
        }
        if (isVisit) WithFriendsField(tags)
        if (!followsFlight) WhenField(whenChoice, { whenChoice = it }, photos)
        // The server's photos count too: a check-in restored on a new phone has none of its own copies here. A photo marked as
        // removed makes room for one more.
        val room = minOf(state.roomForPhotos, CheckInStore.MAX_PHOTOS - existing.size).coerceAtLeast(0) + removed.size
        if (room > 0 || existing.isNotEmpty()) PhotoField(photos, room, existing, removed, { removed = removed + it.id }) { photos = it }
        if (deleteFailed) Text(stringResource(R.string.delete_photo_failed), color = MaterialTheme.colorScheme.error)
        VisibilityRow(app, checkIn.id.toString())
        SaveBar(
            state, enabled = isVisit || (hasAircraft && (input.isBlank() || registration != null)),
            onSave = {
                saveScope.launch {
                    deleteFailed = !deleteRemoved(existing, removed, onDeletePhoto) { removed = it }
                    if (!deleteFailed) model.saveSimpleEdit(checkIn.id, registration, type?.icaoCode ?: keptType, if (isVisit) reason else null, photos, if (isVisit) tags.ifChanged() else null, spotChange, newMoment)
                }
            },
            onCancel = model::cancelEdit,
        )
    }
}

/**
 * Deletes the photos that were marked as removed in an edit screen, one after the other. Returns false at the first one that fails,
 * and nothing else is saved then, so the person can try again or cancel. [onLeft] gets the ids still marked.
 */
private suspend fun deleteRemoved(existing: List<FeedPhoto>, removed: Set<String>, delete: suspend (FeedPhoto) -> Boolean, onLeft: (Set<String>) -> Unit): Boolean {
    var left = removed
    for (photo in existing.filter { it.id in removed }) {
        if (!delete(photo)) { onLeft(left); return false }
        left = left - photo.id
    }
    onLeft(left)
    return true
}

@Composable
private fun FlightDetails(
    flightNumber: String, onFlightNumber: (String) -> Unit, input: String, onInput: (String) -> Unit, registration: Registration?,
    reference: ReferenceState, type: AircraftType?, onType: (AircraftType?) -> Unit,
    cabin: CabinClass?, onCabin: (CabinClass?) -> Unit, seat: String, onSeat: (String) -> Unit, keptType: String? = null,
    recentTypes: List<String> = emptyList(),
) {
    OutlinedTextField(
        value = flightNumber, onValueChange = onFlightNumber, singleLine = true,
        label = { Text(stringResource(R.string.flight_number_label)) }, modifier = Modifier.fillMaxWidth(),
    )
    OutlinedTextField(
        value = input, onValueChange = onInput, singleLine = true,
        label = { Text(stringResource(R.string.registration_label)) }, modifier = Modifier.fillMaxWidth(),
    )
    RegistrationHint(input, registration, orType = false)
    if (keptType != null) Text(stringResource(R.string.type_kept, keptType), style = MaterialTheme.typography.bodySmall)
    TypePicker(reference, type, recentTypes, onType)
    Text(stringResource(R.string.cabin_label), style = MaterialTheme.typography.labelLarge)
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for (option in CabinClass.entries) {
            FilterChip(selected = cabin == option, onClick = { onCabin(if (cabin == option) null else option) }, label = { Text(stringResource(cabinTitle(option))) })
        }
    }
    OutlinedTextField(
        value = seat, onValueChange = onSeat, singleLine = true,
        label = { Text(stringResource(R.string.seat_label)) }, modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun RegistrationHint(input: String, registration: Registration?, orType: Boolean) {
    when {
        registration != null -> Text(
            stringResource(R.string.registration_valid, registration.value, registration.countryCode),
            fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.titleLarge,
        )
        input.isNotBlank() -> Text(stringResource(R.string.registration_invalid))
        orType -> Text(stringResource(R.string.registration_or_type), style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun TypePicker(reference: ReferenceState, type: AircraftType?, recent: List<String> = emptyList(), onPick: (AircraftType?) -> Unit) {
    // The types of earlier flights with this flight number, named from the reference data on the phone.
    val all = LocalCheckIns.current
    val latest = remember(all) { RecentTypes.types(all) }
    val suggestions by produceState(emptyList<AircraftType>() to emptyList<AircraftType>(), recent, latest, reference.database) {
        val db = reference.database
        value = recent.mapNotNull { db?.aircraftType(it) } to latest.filter { it !in recent }.mapNotNull { db?.aircraftType(it) }
    }
    Picker(
        label = stringResource(R.string.type_label), chosen = type?.let { "${it.icaoCode}  ${it.name}" },
        onClear = { onPick(null) },
        search = { text -> reference.database?.searchTypes(text, 5).orEmpty() },
        rowTitle = { it.icaoCode }, rowDetail = { it.name }, onPick = { onPick(it) },
        suggestions = listOf(
            stringResource(R.string.recent_types) to suggestions.first,
            stringResource(R.string.recent_types_overall) to suggestions.second,
        ),
    )
}

/** The airport search for other screens, such as the home airport. */
@Composable
fun AirportPickerPublic(reference: ReferenceState, airport: Airport?, onPick: (Airport?) -> Unit) =
    AirportPicker(stringResource(R.string.airport_label), reference, airport, onPick)

@Composable
private fun AirportPicker(label: String, reference: ReferenceState, airport: Airport?, onPick: (Airport?) -> Unit) {
    // The airports of your latest check-ins, named from the reference data on the phone.
    val all = LocalCheckIns.current
    val recent by produceState(emptyList<Airport>(), all, reference.database) {
        value = RecentTypes.airportIds(all).mapNotNull { reference.database?.airport(it) }
    }
    Picker(
        label = label, chosen = airport?.let { "${it.code}  ${it.name}" }, onClear = { onPick(null) },
        search = { text -> reference.database?.searchAirports(text, 5).orEmpty() },
        rowTitle = { it.code }, rowDetail = { it.name }, onPick = { onPick(it) },
        suggestions = listOf(stringResource(R.string.recent_airports) to recent),
    )
}

/** Every check-in on this phone, for the suggestions the pickers offer before anything is typed. */
val LocalCheckIns = androidx.compose.runtime.compositionLocalOf<List<LocalCheckIn>> { emptyList() }

/**
 * The photos part of a form: pick several at once with the system photo picker (it needs no permission, and the app sees
 * only the pictures that were chosen), see thumbnails and remove the ones you don't want. The photos keep the order they
 * were picked in, and the first one is the cover. [limit] is how many the check-in can take in all. Create and edit forms
 * all use this.
 */
@Composable
private fun PhotoField(
    photos: List<PreparedPhoto>, limit: Int = CheckInStore.MAX_PHOTOS,
    /** The photos the check-in already has on the server, for the edit screens. */
    existing: List<FeedPhoto> = emptyList(),
    /** The existing photos marked as removed with the cross. The edit screen deletes them when it is saved. */
    removedIds: Set<String> = emptySet(), onRemoveExisting: ((FeedPhoto) -> Unit)? = null,
    onPhotos: (List<PreparedPhoto>) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var failed by remember { mutableStateOf(false) }
    var preparing by remember { mutableStateOf(false) }
    val room = limit - photos.size
    // Read when the pictures come back, so a second pick sees the photos of the first.
    val current by androidx.compose.runtime.rememberUpdatedState(photos)
    fun prepare(uris: List<android.net.Uri>) {
        if (uris.isEmpty()) return
        scope.launch {
            preparing = true
            var bad = false
            var all = current
            for (uri in uris) {
                if (all.size >= limit) break
                val prepared = PhotoPrep.prepare(context, uri)
                if (prepared == null) bad = true else all = all + prepared
            }
            onPhotos(all)
            failed = bad
            preparing = false
        }
    }
    // The multiple picker needs a maximum of at least 2, so the last free place uses the single picker.
    val pickMany = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(maxOf(2, room))) { uris -> prepare(uris) }
    val pickOne = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> if (uri != null) prepare(listOf(uri)) }
    val shownExisting = existing.filterNot { it.id in removedIds }
    if (photos.isNotEmpty() || shownExisting.isNotEmpty()) {
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            shownExisting.forEach { photo ->
                Box(Modifier.size(96.dp).clip(MaterialTheme.shapes.small)) {
                    RemoteImage(photo, Modifier.fillMaxSize())
                    if (onRemoveExisting != null) Box(
                        Modifier.align(Alignment.TopEnd).padding(4.dp).size(28.dp)
                            .clip(androidx.compose.foundation.shape.CircleShape)
                            .background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.6f))
                            .clickable { onRemoveExisting(photo) }
                            .semantics { contentDescription = context.getString(R.string.remove_photo) },
                        contentAlignment = Alignment.Center,
                    ) { Text("\u2715", color = androidx.compose.ui.graphics.Color.White) }
                }
            }
            photos.forEachIndexed { index, photo ->
                val bitmap = remember(photo) { BitmapFactory.decodeByteArray(photo.jpeg, 0, photo.jpeg.size)?.asImageBitmap() }
                Box(Modifier.size(96.dp).clip(MaterialTheme.shapes.small)) {
                    if (bitmap != null) Image(bitmap, contentDescription = stringResource(R.string.photo_of_check_in), contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                    // A dark disc under the cross, so it shows on light pictures too.
                    Box(
                        Modifier.align(Alignment.TopEnd).padding(4.dp).size(28.dp)
                            .clip(androidx.compose.foundation.shape.CircleShape)
                            .background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.6f))
                            .clickable { onPhotos(photos.filterIndexed { i, _ -> i != index }) }
                            .semantics { contentDescription = context.getString(R.string.remove_photo) },
                        contentAlignment = Alignment.Center,
                    ) { Text("\u2715", color = androidx.compose.ui.graphics.Color.White) }
                }
            }
        }
    }
    if (room > 0) {
        OutlinedButton(
            onClick = {
                if (room > 1) pickMany.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                else pickOne.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            },
            enabled = !preparing,
            modifier = Modifier.fillMaxWidth().testTag("add-photo"),
        ) { Text(stringResource(if (preparing) R.string.reading else if (room > 1) R.string.add_photos else R.string.add_photo)) }
        Text(stringResource(R.string.photo_hint), style = MaterialTheme.typography.bodySmall)
    }
    if (removedIds.isNotEmpty()) Text(stringResource(R.string.removed_photos_note), style = MaterialTheme.typography.bodySmall)
    if (failed) Text(stringResource(R.string.photo_failed), color = MaterialTheme.colorScheme.error)
}

@Composable
private fun SaveBar(state: CheckInState, enabled: Boolean, onSave: () -> Unit, onCancel: () -> Unit) {
    if (state.saveFailed) Text(stringResource(R.string.error_unknown), color = MaterialTheme.colorScheme.error)
    Button(onClick = onSave, enabled = enabled, modifier = Modifier.fillMaxWidth().testTag("save")) { Text(stringResource(R.string.save)) }
    TextButton(onClick = onCancel) { Text(stringResource(R.string.cancel)) }
}

/** A search box that offers a few matches; picking one fills it in. */
@Composable
private fun <T> Picker(
    label: String, chosen: String?, onClear: () -> Unit, search: suspend (String) -> List<T>,
    rowTitle: (T) -> String, rowDetail: (T) -> String, onPick: (T) -> Unit,
    suggestions: List<Pair<String, List<T>>> = emptyList(),
) {
    if (chosen != null) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(chosen, modifier = Modifier.weight(1f))
            TextButton(onClick = onClear) { Text(stringResource(R.string.clear)) }
        }
        return
    }
    var text by rememberSaveable { mutableStateOf("") }
    var matches by remember { mutableStateOf(emptyList<T>()) }
    LaunchedEffect(text) {
        delay(250)
        matches = if (text.isBlank()) emptyList() else search(text)
    }
    OutlinedTextField(
        value = text, onValueChange = { text = it }, singleLine = true,
        label = { Text(label) }, modifier = Modifier.fillMaxWidth(),
    )
    @Composable
    fun Row(match: T) {
        TextButton(onClick = { onPick(match); text = "" }, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.fillMaxWidth()) {
                Text(rowTitle(match), style = MaterialTheme.typography.titleSmall)
                Text(rowDetail(match), style = MaterialTheme.typography.bodySmall)
            }
        }
    }
    if (text.isBlank()) {
        for ((title, items) in suggestions) {
            if (items.isEmpty()) continue
            Text(title, style = MaterialTheme.typography.labelLarge)
            items.forEach { Row(it) }
        }
    } else {
        matches.forEach { Row(it) }
    }
}

@Composable
private fun ResultView(result: SavedResult, onReturn: (() -> Unit)?, onAnother: () -> Unit, onDone: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(result.title, style = MaterialTheme.typography.displaySmall, fontFamily = FontFamily.Monospace)
        when (result.kind) {
            Kind.SPOTTED -> if (result.count <= 1) {
                Text(stringResource(R.string.first_time), style = MaterialTheme.typography.titleLarge)
            } else {
                Text(stringResource(R.string.seen_again, result.count), style = MaterialTheme.typography.titleLarge)
                result.lastSeen?.let {
                    Text(stringResource(R.string.last_time, DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(it.atZone(ZoneId.systemDefault()))))
                }
            }
            Kind.AIRPORT -> Text(
                stringResource(if (result.count <= 1) R.string.airport_first else R.string.airport_again, result.count),
                style = MaterialTheme.typography.titleLarge,
            )
            Kind.FLOWN -> {
                Text(
                    stringResource(if (result.count <= 1) R.string.route_first else R.string.route_again, result.count),
                    style = MaterialTheme.typography.titleLarge,
                )
                if (result.trackPositions > 0) {
                    Text(stringResource(R.string.track_saved, result.trackPositions), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        if (onReturn != null && result.kind == Kind.FLOWN) {
            Button(onClick = onReturn, modifier = Modifier.fillMaxWidth().testTag("return-flight")) { Text(stringResource(R.string.return_flight)) }
            OutlinedButton(onClick = onAnother, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.check_in_another)) }
        } else {
            Button(onClick = onAnother, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.check_in_another)) }
        }
        OutlinedButton(onClick = onDone, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.done)) }
    }
}

/** The last check-ins on this phone, with whether the server has them yet, and a menu to edit or delete each. */
@Composable
fun RecentCheckIns(items: List<LocalCheckIn>, onEdit: (UUID) -> Unit, onDelete: (UUID) -> Unit) {
    if (items.isEmpty()) return
    var deleting by remember { mutableStateOf<LocalCheckIn?>(null) }
    HorizontalDivider()
    Text(stringResource(R.string.recent_title), style = MaterialTheme.typography.titleMedium)
    items.forEach { c ->
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(c.title, fontFamily = FontFamily.Monospace)
                Text(
                    stringResource(kindTitle(c.kind)) + " · " + stringResource(
                        when (c.syncState) {
                            SyncState.PENDING -> R.string.state_pending
                            SyncState.SYNCED -> R.string.state_synced
                            SyncState.REJECTED -> R.string.state_rejected
                        },
                    ),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            var open by remember { mutableStateOf(false) }
            Box {
                // A full-size touch target: small icon buttons are hard to hit.
                IconButton(onClick = { open = true }, modifier = Modifier.size(48.dp).testTag("more-${c.id}")) { Text("⋮", style = MaterialTheme.typography.titleLarge) }
                DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                    if (c.kind == "flown") {
                        DropdownMenuItem(text = { Text(stringResource(R.string.edit_details)) }, onClick = { open = false; onEdit(c.id) })
                    }
                    DropdownMenuItem(text = { Text(stringResource(R.string.delete)) }, onClick = { open = false; deleting = c })
                }
            }
        }
    }
    deleting?.let { c ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text(stringResource(R.string.delete_title)) },
            text = { Text(stringResource(R.string.delete_message)) },
            confirmButton = { TextButton(onClick = { deleting = null; onDelete(c.id) }) { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

private fun kindTitle(kind: String) = when (kind) {
    "flown" -> R.string.flown_title
    "airport" -> R.string.airport_title
    else -> R.string.spotted_title
}

private fun visitTitle(context: VisitContext) = when (context) {
    VisitContext.SPOTTING -> R.string.visit_spotting
    VisitContext.DEPARTING -> R.string.visit_departing
    VisitContext.ARRIVING -> R.string.visit_arriving
    VisitContext.TRANSIT -> R.string.visit_transit
    VisitContext.WORKING -> R.string.visit_working
    VisitContext.MUSEUM -> R.string.visit_museum
}

internal fun cabinTitle(cabin: CabinClass) = when (cabin) {
    CabinClass.ECONOMY -> R.string.cabin_economy
    CabinClass.PREMIUM_ECONOMY -> R.string.cabin_premium
    CabinClass.BUSINESS -> R.string.cabin_business
    CabinClass.FIRST -> R.string.cabin_first
}
