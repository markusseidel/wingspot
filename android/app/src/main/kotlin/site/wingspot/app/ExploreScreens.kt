package site.wingspot.app

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.ZoneId
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import site.wingspot.core.ActiveAirport
import site.wingspot.core.AircraftType
import site.wingspot.core.Activity
import site.wingspot.core.Airport
import site.wingspot.core.ApiException
import site.wingspot.core.CheckInStats
import site.wingspot.core.Collections
import site.wingspot.core.FeedCursor
import site.wingspot.core.FeedItem
import site.wingspot.core.FeedPhoto
import site.wingspot.core.LocalCheckIn
import site.wingspot.core.Person

/** A registration has letters and a digit or a hyphen, such as D-AIPC or N123AB. Whether it exists is the server's answer. */
fun looksLikeRegistration(text: String): Boolean =
    Regex("^[A-Za-z0-9]{1,2}-?[A-Za-z0-9]{2,5}$").matches(text) && (text.contains('-') || text.any { it.isDigit() })

/** The Explore tab: one search for people, airports and aircraft types, and the airports near you. */
@Composable
fun ExploreTab(app: WingspotApp, model: SocialViewModel, me: String?, reference: ReferenceState, local: List<LocalCheckIn>) {
    var query by remember { mutableStateOf("") }
    var airports by remember { mutableStateOf(emptyList<Airport>()) }
    var types by remember { mutableStateOf(emptyList<AircraftType>()) }
    var people by remember { mutableStateOf(emptyList<Person>()) }
    val trimmed = query.trim()
    val searching = trimmed.length >= 2
    // People are found only by someone who is signed in and has agreed to the rules.
    val canSearchPeople = me != null && app.terms.hasAccepted(me)

    LaunchedEffect(trimmed, reference.database, canSearchPeople) {
        if (!searching) { airports = emptyList(); types = emptyList(); people = emptyList(); return@LaunchedEffect }
        delay(250)
        val db = reference.database
        airports = db?.searchAirports(trimmed, 8).orEmpty()
        types = db?.searchTypes(trimmed, 8).orEmpty()
        people = if (canSearchPeople) try { app.social.searchPeople(trimmed, me!!, 8) } catch (e: ApiException) { emptyList() } else emptyList()
    }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth().padding(top = 16.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            Text(stringResource(R.string.tab_explore), style = MaterialTheme.typography.headlineMedium, modifier = Modifier.weight(1f))
            OutlinedButton(onClick = { model.open(Route.ExploreMap) }, modifier = Modifier.testTag("explore-map")) { Text(stringResource(R.string.map)) }
        }
        OutlinedTextField(
            value = query, onValueChange = { query = it }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("explore-search"),
            label = { Text(stringResource(R.string.search_everything)) },
            trailingIcon = { if (query.isNotEmpty()) TextButton(onClick = { query = "" }) { Text(stringResource(R.string.clear)) } },
        )
        if (searching) {
            if (people.isNotEmpty()) {
                SectionTitle(R.string.tab_people)
                people.forEach { person ->
                    Column(Modifier.fillMaxWidth().clickable { model.openPerson(person.id) }.padding(vertical = 8.dp)) {
                        Text(person.who, fontWeight = FontWeight.Bold)
                        Text("@" + person.username, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            if (canSearchPeople && looksLikeRegistration(trimmed)) {
                SectionTitle(R.string.tab_aircraft)
                TextButton(onClick = { model.open(Route.RegistrationPage(trimmed)) }) { Text(stringResource(R.string.look_up, trimmed.uppercase())) }
            }
            if (airports.isNotEmpty()) {
                SectionTitle(R.string.airports)
                airports.forEach { AirportRow(it, null) { model.open(Route.AirportPage(it.id)) } }
            }
            if (types.isNotEmpty()) {
                val mine = Collections.of(local).types.associate { it.id to it.count }
                SectionTitle(R.string.aircraft_types)
                types.forEach { type ->
                    Row(Modifier.fillMaxWidth().clickable { model.open(Route.TypePage(type.icaoCode)) }.padding(vertical = 8.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(type.icaoCode, fontWeight = FontWeight.Bold)
                            Text(type.name, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        mine[type.icaoCode]?.let { Text("$it×", fontWeight = FontWeight.Bold) }
                    }
                }
            }
            if (people.isEmpty() && airports.isEmpty() && types.isEmpty() && !(canSearchPeople && looksLikeRegistration(trimmed))) {
                Text(stringResource(R.string.nothing_found), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (!canSearchPeople) Text(stringResource(R.string.sign_in_to_find_people), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            NearbyAirports(app, model, reference)
            if (canSearchPeople) BusyAirports(app, model)
        }
    }
}

@Composable
private fun SectionTitle(res: Int) {
    Text(stringResource(res), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp))
}

@Composable
private fun AirportRow(airport: Airport, distanceKm: Double?, onClick: () -> Unit) {
    val unit = (LocalContext.current.applicationContext as WingspotApp).prefs.unit
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 8.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(airport.code, fontWeight = FontWeight.Bold)
            Text(listOfNotNull(airport.name, airport.city).filter { it.isNotBlank() }.joinToString(", "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        distanceKm?.let { Text(unit.format(Math.round(it).toInt()), style = MaterialTheme.typography.bodySmall) }
    }
}

/** The position the phone last knew, from the network or the passive provider. Null without permission or a position. */
@SuppressLint("MissingPermission")
private fun lastPosition(context: Context): Pair<Double, Double>? {
    if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) return null
    val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    val best = manager.getProviders(true).mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }.maxByOrNull { it.time } ?: return null
    return best.latitude to best.longitude
}

/** Airports close to the phone. It asks for the location only when the person taps, and remembers that they did. */
@Composable
private fun NearbyAirports(app: WingspotApp, model: SocialViewModel, reference: ReferenceState) {
    val context = LocalContext.current
    var nearby by remember { mutableStateOf(emptyList<Pair<Airport, Double>>()) }
    var unavailable by remember { mutableStateOf(false) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) app.prefs.chooseLocation(true) else unavailable = true
    }
    LaunchedEffect(app.prefs.usesLocation, reference.database) {
        val db = reference.database ?: return@LaunchedEffect
        if (!app.prefs.usesLocation) return@LaunchedEffect
        val position = lastPosition(context)
        if (position == null) { unavailable = true; return@LaunchedEffect }
        unavailable = false
        nearby = db.airportsNear(position.first, position.second, 150.0, 10)
    }
    SectionTitle(R.string.airports_near_you)
    when {
        reference.database == null -> Text(stringResource(R.string.no_airport_data))
        !app.prefs.usesLocation -> {
            Button(onClick = { launcher.launch(Manifest.permission.ACCESS_COARSE_LOCATION) }) { Text(stringResource(R.string.show_airports_near_me)) }
            Text(stringResource(R.string.location_note), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        unavailable -> Text(stringResource(R.string.location_unavailable))
        nearby.isEmpty() -> Text(stringResource(R.string.no_airports_near), color = MaterialTheme.colorScheme.onSurfaceVariant)
        else -> nearby.forEach { (airport, km) -> AirportRow(airport, km) { model.open(Route.AirportPage(airport.id)) } }
    }
}

/** The airports with the most check-ins in the last week among the ones you may see. */
@Composable
private fun BusyAirports(app: WingspotApp, model: SocialViewModel) {
    var airports by remember { mutableStateOf<List<ActiveAirport>?>(null) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { try { airports = app.social.activeAirports(7, 10); failed = false } catch (e: ApiException) { failed = true } }
    SectionTitle(R.string.busy_this_week)
    val list = airports
    when {
        failed -> Text(stringResource(R.string.load_failed), color = MaterialTheme.colorScheme.error)
        list == null -> CircularProgressIndicator()
        list.isEmpty() -> Text(stringResource(R.string.nothing_this_week), color = MaterialTheme.colorScheme.onSurfaceVariant)
        else -> list.forEach { a ->
            Row(Modifier.fillMaxWidth().clickable { model.open(Route.AirportPage(a.airportId)) }.padding(vertical = 8.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(a.code, fontWeight = FontWeight.Bold)
                    Text(listOfNotNull(a.name, a.city).filter { it.isNotBlank() }.joinToString(", "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text(stringResource(R.string.n_check_ins, a.checkIns), style = MaterialTheme.typography.bodySmall)
            }
        }
    }
    Text(stringResource(R.string.counts_note), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

// Pages ------------------------------------------------------------------------------------------------------------

/** What others recently checked in, a page at a time, for an airport, a type or a registration. */
@Composable
private fun RecentList(app: WingspotApp, model: SocialViewModel, me: String?, fetch: suspend (FeedCursor?) -> List<FeedItem>, onTypeFound: (FeedItem) -> Unit = {}) {
    val scope = rememberCoroutineScope()
    var items by remember { mutableStateOf(emptyList<FeedItem>()) }
    var photos by remember { mutableStateOf(emptyMap<String, List<FeedPhoto>>()) }
    var loaded by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    var more by remember { mutableStateOf(false) }
    suspend fun load(after: FeedCursor?) {
        try {
            val got = fetch(after)
            items = if (after == null) got else items + got
            more = got.size >= 30
            photos = photos + runCatching { app.social.photos(got.map { it.id }).groupBy { it.checkInId } }.getOrDefault(emptyMap())
            got.firstOrNull()?.let(onTypeFound)
            failed = false
        } catch (e: ApiException) { failed = true }
        loaded = true
    }
    LaunchedEffect(me) { if (me != null) load(null) }
    SectionTitle(R.string.recent_check_ins)
    when {
        me == null -> Text(stringResource(R.string.sign_in_to_see_others))
        failed && items.isEmpty() -> Text(stringResource(R.string.load_failed), color = MaterialTheme.colorScheme.error)
        loaded && items.isEmpty() -> Text(stringResource(R.string.nothing_to_show_yet), color = MaterialTheme.colorScheme.onSurfaceVariant)
        !loaded -> CircularProgressIndicator()
    }
    items.forEach { item ->
        FeedCard(item, me.orEmpty(), photos[item.id].orEmpty(), onOpen = { model.open(item) }, onSalute = {
            val on = !item.saluted
            items = items.map { if (it.id == item.id) it.copy(saluted = on, salutes = (it.salutes + if (on) 1 else -1).coerceAtLeast(0)) else it }
            scope.launch { try { app.social.setSalute(on, item.id, me!!) } catch (e: ApiException) { items = items.map { if (it.id == item.id) item else it } } }
        }, onPerson = { model.openPerson(item.userId) })
    }
    if (more) TextButton(onClick = { scope.launch { items.lastOrNull()?.let { load(FeedCursor(it.occurredAt, it.id)) } } }) { Text(stringResource(R.string.load_more)) }
}

@Composable
private fun YouSection(count: Int, first: java.time.Instant?, last: java.time.Instant?, emptyText: Int, countLabel: Int = R.string.your_check_ins) {
    SectionTitle(R.string.you)
    if (count == 0 || last == null) { Text(stringResource(emptyText), color = MaterialTheme.colorScheme.onSurfaceVariant); return }
    val format = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
    fun date(i: java.time.Instant) = format.format(i.atZone(ZoneId.systemDefault()))
    Text(stringResource(countLabel, count))
    first?.let { Text(stringResource(R.string.first_time_on, date(it))) }
    Text(stringResource(R.string.last_time, date(last)))
}

@Composable
private fun ActivitySection(app: WingspotApp, me: String?, model: SocialViewModel, otherLabel: Int, load: suspend () -> Activity?) {
    var activity by remember { mutableStateOf<Activity?>(null) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(me) { if (me != null) try { activity = load() } catch (e: ApiException) { failed = true } }
    if (me == null) return
    SectionTitle(R.string.activity)
    val a = activity
    when {
        failed -> Text(stringResource(R.string.load_failed), color = MaterialTheme.colorScheme.error)
        a == null -> CircularProgressIndicator()
        else -> {
            Text(stringResource(R.string.check_ins_30d, a.checkIns))
            Text(stringResource(otherLabel, a.other))
            a.topSpotters.forEach { s ->
                Row(Modifier.fillMaxWidth().clickable(enabled = s.userId != me) { model.openPerson(s.userId) }.padding(vertical = 6.dp)) {
                    Text(if (s.userId == me) stringResource(R.string.you) else s.who, Modifier.weight(1f))
                    Text("${s.checkIns}×")
                }
            }
            Text(stringResource(R.string.counts_note), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
fun AirportPage(app: WingspotApp, model: SocialViewModel, id: Long, me: String?, reference: ReferenceState, local: List<LocalCheckIn>) {
    var airport by remember { mutableStateOf<Airport?>(null) }
    LaunchedEffect(reference.database) { airport = reference.database?.airport(id) }
    val mine = CheckInStats.counted(local).filter { it.airportId == id && it.kind != "flown" }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        PageHeader(airport?.code.orEmpty(), model::back)
        airport?.let { a ->
            Text(a.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(listOfNotNull(listOfNotNull(a.iata, a.icao).joinToString(" · "), a.city).filter { it.isNotBlank() }.joinToString(" — "), color = MaterialTheme.colorScheme.onSurfaceVariant)
            AirportMiniMap(a)
        } ?: if (reference.database == null) Text(stringResource(R.string.no_airport_data)) else CircularProgressIndicator()
        YouSection(mine.size, null, mine.maxOfOrNull { it.occurredAt }, R.string.not_checked_in_here)
        ActivitySection(app, me, model, R.string.different_aircraft) { app.social.airportActivity(id) }
        RecentList(app, model, me, { app.social.airportCheckIns(id, it) })
    }
}

@Composable
fun TypePage(app: WingspotApp, model: SocialViewModel, code: String, me: String?, local: List<LocalCheckIn>) {
    val mine = CheckInStats.counted(local).filter { it.typeIcao == code }
    var name by remember { mutableStateOf<String?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        PageHeader(code, model::back)
        name?.let { Text(it, style = MaterialTheme.typography.titleLarge) }
        YouSection(mine.size, mine.minOfOrNull { it.occurredAt }, mine.maxOfOrNull { it.occurredAt }, R.string.not_seen_type)
        ActivitySection(app, me, model, R.string.different_airports) { app.social.typeActivity(code) }
        RecentList(app, model, me, { app.social.typeCheckIns(code, it) }, onTypeFound = { if (name == null) name = it.typeName })
    }
}

@Composable
fun RegistrationPage(app: WingspotApp, model: SocialViewModel, registration: String, me: String?, local: List<LocalCheckIn>) {
    val normalized = registration.uppercase().filter { it.isLetterOrDigit() }
    val mine = CheckInStats.counted(local).filter { (it.registration ?: "").uppercase().filter(Char::isLetterOrDigit) == normalized }
    var typeCode by remember { mutableStateOf<String?>(null) }
    var typeName by remember { mutableStateOf<String?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        PageHeader(registration.uppercase(), model::back)
        Text(registration.uppercase(), style = MaterialTheme.typography.titleLarge, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold)
        typeName?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        typeCode?.let { code -> OutlinedButton(onClick = { model.open(Route.TypePage(code)) }) { Text(stringResource(R.string.type_page, code)) } }
        YouSection(mine.size, mine.minOfOrNull { it.occurredAt }, mine.maxOfOrNull { it.occurredAt }, R.string.not_seen_aircraft)
        RecentList(app, model, me, { app.social.registrationCheckIns(registration, it) }, onTypeFound = {
            if (typeCode == null) { typeCode = it.typeIcao; typeName = it.typeName }
        })
    }
}
