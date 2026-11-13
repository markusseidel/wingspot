package site.wingspot.app

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
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
import site.wingspot.core.BoardingPass
import site.wingspot.core.Airport
import site.wingspot.core.CabinClass
import site.wingspot.core.LocalCheckIn
import site.wingspot.core.Registration
import site.wingspot.core.SyncState
import site.wingspot.core.VisitContext

/** A check-in: Spotted, Airport or Flown. Saved on the phone first. */
@Composable
fun CheckInScreen(state: CheckInState, reference: ReferenceState, model: CheckInViewModel) {
    val result = state.result
    if (result != null) {
        ResultView(result, onAnother = model::another, onDone = model::close)
        return
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
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
    var photo by remember { mutableStateOf<PreparedPhoto?>(null) }
    val registration = Registration.parse(input)
    val canSave = if (input.isNotBlank()) registration != null else type != null

    Text(stringResource(R.string.spotted_title), style = MaterialTheme.typography.headlineMedium)
    OutlinedTextField(
        value = input, onValueChange = { input = it }, singleLine = true,
        label = { Text(stringResource(R.string.registration_label)) }, modifier = Modifier.fillMaxWidth().testTag("registration"),
    )
    RegistrationHint(input, registration, orType = true)
    if (registration == null) TypePicker(reference, type) { type = it }
    AirportPicker(stringResource(R.string.airport_label), reference, airport) { airport = it }
    PhotoField(photo) { photo = it }
    SaveBar(state, enabled = canSave, onSave = { model.save(registration, type, airport, photo) }, onCancel = model::close)
}

@Composable
private fun AirportForm(state: CheckInState, reference: ReferenceState, model: CheckInViewModel) {
    var airport by remember { mutableStateOf<Airport?>(null) }
    var context by rememberSaveable { mutableStateOf(VisitContext.SPOTTING) }
    var photo by remember { mutableStateOf<PreparedPhoto?>(null) }
    Text(stringResource(R.string.airport_title), style = MaterialTheme.typography.headlineMedium)
    AirportPicker(stringResource(R.string.airport_label), reference, airport) { airport = it }
    Text(stringResource(R.string.why_there), style = MaterialTheme.typography.labelLarge)
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for (option in VisitContext.entries) {
            FilterChip(selected = context == option, onClick = { context = option }, label = { Text(stringResource(visitTitle(option))) })
        }
    }
    PhotoField(photo) { photo = it }
    SaveBar(state, enabled = airport != null, onSave = { model.saveAirport(airport!!, context, photo) }, onCancel = model::close)
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun FlownForm(state: CheckInState, reference: ReferenceState, model: CheckInViewModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var origin by remember { mutableStateOf<Airport?>(null) }
    var destination by remember { mutableStateOf<Airport?>(null) }
    var flightNumber by rememberSaveable { mutableStateOf("") }
    var input by rememberSaveable { mutableStateOf("") }
    var type by remember { mutableStateOf<AircraftType?>(null) }
    var cabin by rememberSaveable { mutableStateOf<CabinClass?>(null) }
    var seat by rememberSaveable { mutableStateOf("") }
    var photo by remember { mutableStateOf<PreparedPhoto?>(null) }
    var date by rememberSaveable { mutableStateOf(LocalDate.now().toString()) }
    var pickDate by remember { mutableStateOf(false) }
    var scanning by remember { mutableStateOf(false) }
    var reading by remember { mutableStateOf(false) }
    var choices by remember { mutableStateOf(emptyList<BoardingPass.Leg>()) }
    var problem by remember { mutableStateOf<Int?>(null) }
    var missing by remember { mutableStateOf("") }
    val registration = Registration.parse(input)
    val sameAirport = origin != null && origin?.id == destination?.id
    val canSave = origin != null && destination != null && !sameAirport && (input.isBlank() || registration != null)
    val day = LocalDate.parse(date)

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

    Text(stringResource(R.string.flown_title), style = MaterialTheme.typography.headlineMedium)
    OutlinedButton(onClick = { scanning = true }, modifier = Modifier.fillMaxWidth().testTag("scan-pass")) { Text(stringResource(R.string.scan_boarding_pass)) }
    OutlinedButton(
        onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, enabled = !reading,
        modifier = Modifier.fillMaxWidth(),
    ) { Text(stringResource(if (reading) R.string.reading else R.string.read_from_picture)) }
    Text(stringResource(R.string.scan_footer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    AirportPicker(stringResource(R.string.from_label), reference, origin) { origin = it }
    AirportPicker(stringResource(R.string.to_label), reference, destination) { destination = it }
    if (sameAirport) Text(stringResource(R.string.same_airport), color = MaterialTheme.colorScheme.error)
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        Text(stringResource(R.string.date_label))
        TextButton(onClick = { pickDate = true }, modifier = Modifier.testTag("flight-date")) { Text(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(day)) }
    }
    FlightDetails(
        flightNumber, { flightNumber = it }, input, { input = it }, registration, reference, type, { type = it }, cabin, { cabin = it }, seat, { seat = it },
    )
    PhotoField(photo) { photo = it }
    SaveBar(
        state, enabled = canSave,
        onSave = {
            // A flight has a day but no time here. Today keeps the real time; any other day uses midday, which stays on that day.
            val at = if (day == LocalDate.now()) java.time.Instant.now() else day.atTime(12, 0).atZone(ZoneId.systemDefault()).toInstant()
            model.saveFlight(origin!!, destination!!, flightNumber, registration, type, cabin, seat, photo, at)
        },
        onCancel = model::close,
    )

    if (pickDate) {
        val startMillis = day.atStartOfDay(java.time.ZoneOffset.UTC).toInstant().toEpochMilli()
        val pickerState = androidx.compose.material3.rememberDatePickerState(
            initialSelectedDateMillis = startMillis,
            selectableDates = object : androidx.compose.material3.SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis <= LocalDate.now().plusDays(1).atStartOfDay(java.time.ZoneOffset.UTC).toInstant().toEpochMilli()
            },
        )
        androidx.compose.material3.DatePickerDialog(
            onDismissRequest = { pickDate = false },
            confirmButton = {
                TextButton(onClick = {
                    pickerState.selectedDateMillis?.let { date = minOf(java.time.Instant.ofEpochMilli(it).atZone(java.time.ZoneOffset.UTC).toLocalDate(), LocalDate.now()).toString() }
                    pickDate = false
                }) { Text(stringResource(R.string.done)) }
            },
            dismissButton = { TextButton(onClick = { pickDate = false }) { Text(stringResource(R.string.cancel)) } },
        ) { androidx.compose.material3.DatePicker(state = pickerState) }
    }
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
    problem?.let { res ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { problem = null },
            title = { Text(stringResource(if (res == R.string.scan_none_found) R.string.scan_none_title else R.string.scan_problem_title)) },
            text = { Text(if (res == R.string.scan_airports_unknown) stringResource(res, missing) else stringResource(res)) },
            confirmButton = { TextButton(onClick = { problem = null }) { Text(stringResource(R.string.ok)) } },
        )
    }
}

/** Fills in or corrects the details of a saved flight. The route, the day and the photos stay as they were. */
@Composable
fun FlownEditScreen(flight: LocalCheckIn, state: CheckInState, reference: ReferenceState, model: CheckInViewModel) {
    var flightNumber by rememberSaveable { mutableStateOf(flight.flightNumber.orEmpty()) }
    var input by rememberSaveable { mutableStateOf(flight.registration.orEmpty()) }
    var type by remember { mutableStateOf<AircraftType?>(null) }
    var cabin by rememberSaveable { mutableStateOf(CabinClass.fromWire(flight.cabin)) }
    var seat by rememberSaveable { mutableStateOf(flight.seat.orEmpty()) }
    val registration = Registration.parse(input)
    // The type this flight already has stays until another is chosen.
    val keptType = flight.typeIcao.takeIf { type == null }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.edit_flight), style = MaterialTheme.typography.headlineMedium)
        Text(flight.title, style = MaterialTheme.typography.titleLarge, fontFamily = FontFamily.Monospace)
        FlightDetails(
            flightNumber, { flightNumber = it }, input, { input = it }, registration, reference, type, { type = it }, cabin, { cabin = it }, seat, { seat = it },
            keptType = keptType,
        )
        SaveBar(
            state, enabled = input.isBlank() || registration != null,
            onSave = { model.saveEdit(flight.id, registration, type, keptType, flightNumber, cabin, seat) }, onCancel = model::cancelEdit,
        )
    }
}

@Composable
private fun FlightDetails(
    flightNumber: String, onFlightNumber: (String) -> Unit, input: String, onInput: (String) -> Unit, registration: Registration?,
    reference: ReferenceState, type: AircraftType?, onType: (AircraftType?) -> Unit,
    cabin: CabinClass?, onCabin: (CabinClass?) -> Unit, seat: String, onSeat: (String) -> Unit, keptType: String? = null,
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
    TypePicker(reference, type, onType)
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
private fun TypePicker(reference: ReferenceState, type: AircraftType?, onPick: (AircraftType?) -> Unit) {
    Picker(
        label = stringResource(R.string.type_label), chosen = type?.let { "${it.icaoCode}  ${it.name}" },
        onClear = { onPick(null) },
        search = { text -> reference.database?.searchTypes(text, 5).orEmpty() },
        rowTitle = { it.icaoCode }, rowDetail = { it.name }, onPick = { onPick(it) },
    )
}

/** The airport search for other screens, such as the home airport. */
@Composable
fun AirportPickerPublic(reference: ReferenceState, airport: Airport?, onPick: (Airport?) -> Unit) =
    AirportPicker(stringResource(R.string.airport_label), reference, airport, onPick)

@Composable
private fun AirportPicker(label: String, reference: ReferenceState, airport: Airport?, onPick: (Airport?) -> Unit) {
    Picker(
        label = label, chosen = airport?.let { "${it.code}  ${it.name}" }, onClear = { onPick(null) },
        search = { text -> reference.database?.searchAirports(text, 5).orEmpty() },
        rowTitle = { it.code }, rowDetail = { it.name }, onPick = { onPick(it) },
    )
}

/** The system photo picker: it needs no permission, and the app sees only the picture that was chosen. */
@Composable
private fun PhotoField(photo: PreparedPhoto?, onPhoto: (PreparedPhoto?) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var failed by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            val prepared = PhotoPrep.prepare(context, uri)
            failed = prepared == null
            if (prepared != null) onPhoto(prepared)
        }
    }
    if (photo != null) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(stringResource(R.string.photo_added, photo.width, photo.height), modifier = Modifier.weight(1f))
            TextButton(onClick = { onPhoto(null) }) { Text(stringResource(R.string.remove)) }
        }
    } else {
        OutlinedButton(
            onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
            modifier = Modifier.fillMaxWidth().testTag("add-photo"),
        ) { Text(stringResource(R.string.add_photo)) }
        Text(stringResource(R.string.photo_hint), style = MaterialTheme.typography.bodySmall)
    }
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
    matches.forEach { match ->
        TextButton(onClick = { onPick(match); text = "" }, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.fillMaxWidth()) {
                Text(rowTitle(match), style = MaterialTheme.typography.titleSmall)
                Text(rowDetail(match), style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun ResultView(result: SavedResult, onAnother: () -> Unit, onDone: () -> Unit) {
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
            Kind.FLOWN -> Text(
                stringResource(if (result.count <= 1) R.string.route_first else R.string.route_again, result.count),
                style = MaterialTheme.typography.titleLarge,
            )
        }
        Button(onClick = onAnother, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.check_in_another)) }
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

private fun cabinTitle(cabin: CabinClass) = when (cabin) {
    CabinClass.ECONOMY -> R.string.cabin_economy
    CabinClass.PREMIUM_ECONOMY -> R.string.cabin_premium
    CabinClass.BUSINESS -> R.string.cabin_business
    CabinClass.FIRST -> R.string.cabin_first
}
