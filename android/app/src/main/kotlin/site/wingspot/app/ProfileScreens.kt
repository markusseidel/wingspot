package site.wingspot.app

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.draw.clip
import site.wingspot.core.groupReleaseNotes
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.ui.unit.dp
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import site.wingspot.core.Airport
import site.wingspot.core.ApiException
import site.wingspot.core.CheckInStats
import site.wingspot.core.CollectionDateKind
import site.wingspot.core.CollectionEntry
import site.wingspot.core.CollectionKind
import site.wingspot.core.Collections
import site.wingspot.core.DistanceUnit
import site.wingspot.core.FlightTrack
import site.wingspot.core.YearDistance
import site.wingspot.core.byYear
import site.wingspot.core.FlownRouteStats
import site.wingspot.core.GeoCoordinate
import site.wingspot.core.GreatCircle
import site.wingspot.core.LocalCheckIn
import site.wingspot.core.ReferenceDatabase
import site.wingspot.core.SocialApi
import site.wingspot.core.SyncState
import site.wingspot.core.Username

/** The Profile tab: level, numbers, your details, and the account actions. */
@Composable
fun ProfileTab(
    app: WingspotApp, state: AppState, model: AppViewModel, badges: BadgesViewModel, social: SocialViewModel,
    reference: ReferenceState, onSearch: (String) -> Unit, onRetry: () -> Unit, local: List<LocalCheckIn>, onLocalDataChanged: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val session = state.session
    val me = session?.user?.id
    val stats = CheckInStats.of(local)
    val progress by badges.state.collectAsState()
    var mine by remember(me) { mutableStateOf<SocialApi.MyProfile?>(null) }
    var home by remember(me) { mutableStateOf<Airport?>(null) }
    var exporting by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<Int?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    var confirmDeleteAgain by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    var exportedJson by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(me, reference.database) {
        if (me == null) return@LaunchedEffect
        try {
            mine = app.social.myProfile(me)
            home = mine?.homeAirport?.let { id -> reference.database?.airport(id) }
        } catch (e: ApiException) { /* the details just stay empty offline */ }
    }

    val save = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri: Uri? ->
        val text = exportedJson
        exportedJson = null
        if (uri != null && text != null) scope.launch {
            withContext(Dispatchers.IO) { app.contentResolver.openOutputStream(uri)?.use { it.write(text.toByteArray()) } }
        }
    }

    Column(Modifier.fillMaxWidth().verticalScrollState(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.tab_profile), style = MaterialTheme.typography.headlineMedium, modifier = Modifier.padding(top = 16.dp))
        if (session == null) {
            when {
                state.sentTo != null -> CheckEmail(state.sentTo, model::useOtherEmail)
                else -> {
                    EmptyState(R.drawable.ic_tab_profile, stringResource(R.string.empty_profile_title), stringResource(R.string.profile_signed_out), Modifier.padding(bottom = 16.dp))
                    val context = LocalContext.current
                    SignInForm(state.isWorking, model::sendLink, model::signInWithPassword,
                        if (GoogleSignIn.isAvailable) ({ scope.launch { GoogleSignIn.idToken(context)?.let { (token, nonce) -> model.signInWithGoogle(token, nonce) } ?: model.googleFailed() } }) else null)
                }
            }
            state.error?.let { Text(stringResource(it), color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("error")) }
            if (stats.checkIns > 0) StatsCard(stats, reference.database)
            OutlinedButton(onClick = { social.open(Route.Collections) }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.collections)) }
            OutlinedButton(onClick = { social.open(Route.Leaderboard) }, modifier = Modifier.fillMaxWidth().testTag("open-leaderboard")) { Text(stringResource(R.string.leaderboard_title)) }
            OutlinedButton(onClick = { social.open(Route.Invite) }, modifier = Modifier.fillMaxWidth().testTag("open-invite")) { Text(stringResource(R.string.invite_title)) }
        } else {
            progress.progress?.let { LevelHeader(it) }
            StatsCard(stats, reference.database)
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(Modifier.padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        Avatar(session.user.id, mine?.who ?: "?", 64.dp)
                        Column {
                            Text(mine?.who ?: "…", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                            mine?.username?.let { Text("@$it", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                            StaffLabel(app, session.user.id)
                        }
                    }
                    Detail(stringResource(R.string.username_label), mine?.username?.let { "@$it" } ?: "…")
                    mine?.displayName?.let { Detail(stringResource(R.string.name_label), it) }
                    home?.let { Detail(stringResource(R.string.home_airport), "${it.code} · ${it.name}") }
                    Detail(stringResource(R.string.signed_in_as_short), session.user.email ?: session.user.id)
                }
            }
            for ((label, route) in listOf(R.string.collections to Route.Collections, R.string.leaderboard_title to Route.Leaderboard, R.string.invite_title to Route.Invite, R.string.edit_profile to Route.EditProfile, R.string.settings to Route.Settings)) {
                OutlinedButton(onClick = { social.open(route) }, modifier = Modifier.fillMaxWidth().testTag("profile-$label")) { Text(stringResource(label)) }
            }
            var canReview by remember { mutableStateOf(false) }
            LaunchedEffect(session.user.id) { canReview = try { "review_spots" in app.social.myPermissions() } catch (e: ApiException) { false } }
            if (canReview) {
                OutlinedButton(onClick = { social.open(Route.ReviewSpots) }, modifier = Modifier.fillMaxWidth().testTag("open-review-spots")) { Text(stringResource(R.string.review_places)) }
            }
            HorizontalDivider()
            OutlinedButton(
                enabled = !exporting, modifier = Modifier.fillMaxWidth(),
                onClick = {
                    exporting = true
                    scope.launch {
                        try { exportedJson = app.social.exportMyData(); save.launch("wingspot-export-${LocalDate.now()}.json") } catch (e: ApiException) { problem = R.string.export_failed }
                        exporting = false
                    }
                },
            ) { Text(stringResource(R.string.export_data)) }
            Text(stringResource(R.string.export_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedButton(onClick = { scope.launch { Push.unregister(app); social.clear(); PhotoCache.clear(app); badges.begin(null); model.signOut() } }, modifier = Modifier.fillMaxWidth().testTag("sign-out")) { Text(stringResource(R.string.sign_out)) }
            Text(stringResource(R.string.sign_out_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            TextButton(onClick = { confirmDelete = true }, enabled = !deleting, modifier = Modifier.testTag("delete-account")) {
                Text(stringResource(R.string.delete_account), color = MaterialTheme.colorScheme.error)
            }
            Text(stringResource(R.string.delete_account_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            problem?.let { Text(stringResource(it), color = MaterialTheme.colorScheme.error) }
        }
        HorizontalDivider()
        SearchSection(reference, onSearch, onRetry)
    }

    if (confirmDelete) AlertDialog(
        onDismissRequest = { confirmDelete = false },
        title = { Text(stringResource(R.string.delete_account_q)) },
        text = { Text(stringResource(R.string.delete_account_message)) },
        confirmButton = { TextButton(onClick = { confirmDelete = false; confirmDeleteAgain = true }) { Text(stringResource(R.string.continue_label), color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.cancel)) } },
    )
    if (confirmDeleteAgain) AlertDialog(
        onDismissRequest = { confirmDeleteAgain = false },
        title = { Text(stringResource(R.string.delete_account_for_good)) },
        text = { Text(stringResource(R.string.delete_account_no_undo)) },
        confirmButton = {
            TextButton(modifier = Modifier.testTag("confirm-delete-account"), onClick = {
                confirmDeleteAgain = false
                deleting = true
                scope.launch {
                    try {
                        model.deleteAccount()
                        social.clear(); badges.begin(null)
                        me?.let { app.prefs.forget(it) }
                        app.checkIns.deleteEverything()
                        onLocalDataChanged()
                    } catch (e: ApiException) {
                        problem = R.string.delete_account_failed
                    }
                    deleting = false
                }
            }) { Text(stringResource(R.string.delete_account), color = MaterialTheme.colorScheme.error) }
        },
        dismissButton = { TextButton(onClick = { confirmDeleteAgain = false }) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun Detail(label: String, value: String) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
        Text(value, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun StatsCard(stats: CheckInStats, database: ReferenceDatabase?) {
    val unit = (LocalContext.current.applicationContext as WingspotApp).prefs.unit
    // The airports of the flights come from the reference data on this phone, so it works offline.
    val kilometres by produceState(0, stats.routes, database) {
        val db = database ?: return@produceState
        val places = mutableMapOf<Long, GeoCoordinate>()
        for (id in stats.routes.keys.flatMap { listOf(it.first, it.second) }.toSet()) {
            db.airport(id)?.let { places[id] = GeoCoordinate(it.latitude, it.longitude) }
        }
        value = stats.kilometres { places[it] }
    }
    // The real routes of imported flights. They stay on this phone, so only these flights count.
    val app = LocalContext.current.applicationContext as WingspotApp
    val routeStats by produceState<FlownRouteStats?>(null, stats.flightList, database) {
        value = withContext(Dispatchers.IO) {
            val places = mutableMapOf<Long, GeoCoordinate>()
            val db = database
            if (db != null) for (id in stats.flightList.flatMap { listOf(it.origin, it.destination) }.toSet()) {
                db.airport(id)?.let { places[id] = GeoCoordinate(it.latitude, it.longitude) }
            }
            FlownRouteStats.of(stats.flightList.mapNotNull { flight ->
                val track = app.tracks.load(flight.id)?.takeIf { it.size >= 2 } ?: return@mapNotNull null
                val from = places[flight.origin]
                val to = places[flight.destination]
                FlightTrack.lengthKm(track) to if (from != null && to != null) GreatCircle.distanceKm(from, to) else null
            })
        }
    }
    // The same flights, by year.
    val yearStats by produceState(emptyList<YearDistance>(), stats.flightList) {
        value = withContext(Dispatchers.IO) {
            FlownRouteStats.byYear(stats.flightList.mapNotNull { flight ->
                val track = app.tracks.load(flight.id)?.takeIf { it.size >= 2 } ?: return@mapNotNull null
                FlightTrack.lengthKm(track) to flight.year
            })
        }
    }
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Detail(stringResource(R.string.stat_check_ins), stats.checkIns.toString())
            Detail(stringResource(R.string.stat_sightings), stats.sightings.toString())
            Detail(stringResource(R.string.stat_flights), stats.flights.toString())
            if (kilometres > 0) Detail(stringResource(R.string.stat_distance_flown), unit.format(kilometres))
            routeStats?.let { r ->
                Detail(stringResource(R.string.stat_real_distance), unit.format(r.totalKm))
                Detail(stringResource(R.string.stat_routes), r.routes.toString())
                Detail(stringResource(R.string.stat_longest_route), unit.format(r.longestKm))
                if (r.biggestDetourKm > 0) Detail(stringResource(R.string.stat_biggest_detour), "+" + unit.format(r.biggestDetourKm))
                if (yearStats.isNotEmpty()) {
                    Text(stringResource(R.string.stat_distance_by_year), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    yearStats.forEach { Detail(it.year.toString(), unit.format(it.km)) }
                }
                Text(stringResource(R.string.stat_routes_note), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Detail(stringResource(R.string.stat_airport_visits), stats.airportVisits.toString())
            Detail(stringResource(R.string.stat_aircraft), stats.aircraft.toString())
            Detail(stringResource(R.string.stat_types), stats.types.toString())
            Detail(stringResource(R.string.stat_airports), stats.airports.toString())
        }
    }
}

/** What has been seen: aircraft, types and airports, and the flights, from the check-ins on this phone. */
@Composable
fun CollectionsPage(app: WingspotApp, local: List<LocalCheckIn>, social: SocialViewModel, reference: ReferenceState) {
    val tab = social.collectionsTab
    val lists = Collections.of(local)
    val flights = Collections.ordered(Collections.flights(local), app.prefs.collectionDate, app.prefs.collectionAscending)
    val places = airportPlaces(flights.flatMap { listOfNotNull(it.originId, it.destinationId) }.toSet(), reference.database)
    val entries: List<CollectionEntry> = when (tab) { 0 -> lists.aircraft; 1 -> lists.types; 2 -> lists.airports; else -> emptyList() }
    val kind = when (tab) { 0 -> CollectionKind.AIRCRAFT; 1 -> CollectionKind.TYPE; else -> CollectionKind.AIRPORT }
    LazyColumn(state = social.collectionsList, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item { PageHeader(stringResource(R.string.collections), social::back) }
        item { OutlinedButton(onClick = { social.open(Route.AirportsMap) }, modifier = Modifier.fillMaxWidth().testTag("airports-map")) { Text(stringResource(R.string.airports_map)) } }
        item {
            // The tabs scroll sideways, so they stay usable on small screens and with large text.
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for ((i, label) in listOf(R.string.tab_aircraft, R.string.tab_types, R.string.airports, R.string.tab_flights).withIndex()) {
                    FilterChip(selected = tab == i, onClick = { social.collectionsTab = i }, label = { Text(stringResource(label)) })
                }
            }
        }
        if (tab == 3) {
            item { Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { CollectionSortMenu(app) } }
            if (flights.isEmpty()) item { Text(stringResource(R.string.nothing_here_yet), color = MaterialTheme.colorScheme.onSurfaceVariant) }
            items(flights, key = { it.id }) { flight -> FlightRow(app, flight, places) { social.open(Route.CheckInPage(flight.id.toString())) } }
        } else {
            if (entries.isEmpty()) item { Text(stringResource(R.string.nothing_here_yet), color = MaterialTheme.colorScheme.onSurfaceVariant) }
            items(entries, key = { it.id }) { entry ->
                Row(
                    Modifier.fillMaxWidth().clickable { social.open(Route.CollectionDetail(kind, entry.id)) }.padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(entry.title, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.titleMedium)
                        Text(
                            stringResource(R.string.last_seen, DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(entry.lastSeen.atZone(ZoneId.systemDefault()))),
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Text("\u00d7${entry.count}", style = MaterialTheme.typography.titleMedium)
                }
            }
        }
    }
}

/** The airports of these ids from the reference data on this phone, so it works offline. */
@Composable
private fun airportPlaces(ids: Set<Long>, database: ReferenceDatabase?): Map<Long, GeoCoordinate> {
    val places by produceState(emptyMap<Long, GeoCoordinate>(), ids, database) {
        val db = database ?: return@produceState
        value = withContext(Dispatchers.IO) {
            buildMap { for (id in ids) db.airport(id)?.let { put(id, GeoCoordinate(it.latitude, it.longitude)) } }
        }
    }
    return places
}

private fun shortDate(at: java.time.Instant): String =
    DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(at.atZone(ZoneId.systemDefault()))

/** The sort menu: the date to sort by, and newest or oldest first. Remembered between visits. */
@Composable
fun CollectionSortMenu(app: WingspotApp) {
    var open by remember { mutableStateOf(false) }
    val date = app.prefs.collectionDate
    val ascending = app.prefs.collectionAscending
    Box {
        TextButton(onClick = { open = true }, modifier = Modifier.testTag("collection-sort")) { Text(stringResource(R.string.sort_label)) }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            for ((kind, label) in listOf(CollectionDateKind.FLIGHT to R.string.collection_sort_flight, CollectionDateKind.CHECK_IN to R.string.sort_checkin_date)) {
                DropdownMenuItem(
                    text = { Text((if (date == kind) "\u2713 " else "") + stringResource(label)) },
                    onClick = { app.prefs.chooseCollectionSort(kind, ascending); open = false },
                )
            }
            HorizontalDivider()
            for ((up, label) in listOf(false to R.string.sort_newest, true to R.string.sort_oldest)) {
                DropdownMenuItem(
                    text = { Text((if (ascending == up) "\u2713 " else "") + stringResource(label)) },
                    onClick = { app.prefs.chooseCollectionSort(date, up); open = false },
                )
            }
        }
    }
}

/** A flight in the flights tab: the route, the flight number and aircraft, the date and the distance. Opens when the server has it. */
@Composable
private fun FlightRow(app: WingspotApp, flight: LocalCheckIn, places: Map<Long, GeoCoordinate>, onOpen: () -> Unit) {
    val from = flight.originId?.let { places[it] }
    val to = flight.destinationId?.let { places[it] }
    val km = if (from != null && to != null) Math.round(GreatCircle.distanceKm(from, to)).toInt() else null
    val opens = flight.syncState == SyncState.SYNCED
    Row(
        Modifier.fillMaxWidth().then(if (opens) Modifier.clickable(onClick = onOpen) else Modifier).padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(flight.title, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.titleMedium)
            listOfNotNull(flight.flightNumber, flight.registration ?: flight.typeIcao).joinToString(" \u00b7 ").takeIf { it.isNotEmpty() }?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium)
            }
            Text(shortDate(flight.occurredAt), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Column(horizontalAlignment = Alignment.End) {
            km?.let { Text(app.prefs.unit.format(it), style = MaterialTheme.typography.bodyMedium) }
            if (!opens) Text(stringResource(syncStateText(flight.syncState)), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private fun syncStateText(state: SyncState) = when (state) {
    SyncState.PENDING -> R.string.state_pending
    SyncState.SYNCED -> R.string.state_synced
    SyncState.REJECTED -> R.string.state_rejected
}

/** One check-in in a list of an entry: what it is, when, and its state when it is only on this phone. Opens when the server has it. */
@Composable
private fun EntryCheckInRow(checkIn: LocalCheckIn, onOpen: () -> Unit) {
    val opens = checkIn.syncState == SyncState.SYNCED
    val detail = when (checkIn.kind) {
        "flown" -> listOfNotNull(checkIn.flightNumber, checkIn.registration ?: checkIn.typeIcao).joinToString(" \u00b7 ")
        "airport" -> checkIn.airportCode.orEmpty()
        else -> listOfNotNull(checkIn.typeIcao.takeIf { checkIn.registration != null }, checkIn.airportCode).joinToString(" \u00b7 ")
    }
    Row(
        Modifier.fillMaxWidth().then(if (opens) Modifier.clickable(onClick = onOpen) else Modifier).padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(checkIn.title, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.titleMedium)
            if (detail.isNotEmpty()) Text(detail, style = MaterialTheme.typography.bodyMedium)
            Text(shortDate(checkIn.occurredAt), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (!opens) Text(stringResource(syncStateText(checkIn.syncState)), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/**
 * The check-ins behind one entry of the collections. The number of check-ins here is the count in the list, because both
 * come from the same rule.
 */
@Composable
fun CollectionDetailPage(app: WingspotApp, kind: CollectionKind, key: String, local: List<LocalCheckIn>, social: SocialViewModel, reference: ReferenceState) {
    val checkIns = Collections.checkIns(kind, key, local)
    val shown = Collections.ordered(checkIns, app.prefs.collectionDate, app.prefs.collectionAscending)
    val airportId = checkIns.firstNotNullOfOrNull { it.airportId }
    val airportName by produceState<String?>(null, kind, airportId, reference.database) {
        val db = reference.database
        if (kind == CollectionKind.AIRPORT && airportId != null && db != null) value = withContext(Dispatchers.IO) { db.airport(airportId)?.name }
    }
    val subtitle = airportName ?: checkIns.firstNotNullOfOrNull { it.typeIcao }.takeIf { kind == CollectionKind.AIRCRAFT }
    LazyColumn(state = social.detailList("$kind:$key"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item { PageHeader(key, social::back) }
        item {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                subtitle?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                Detail(stringResource(R.string.stat_check_ins), checkIns.size.toString())
                checkIns.minOfOrNull { it.occurredAt }?.let { Detail(stringResource(R.string.first_label), shortDate(it)) }
                checkIns.maxOfOrNull { it.occurredAt }?.let { Detail(stringResource(R.string.last_label), shortDate(it)) }
                // The page everybody sees for this aircraft, type or airport.
                when (kind) {
                    CollectionKind.AIRCRAFT -> TextButton(onClick = { social.open(Route.RegistrationPage(key)) }) { Text(stringResource(R.string.public_page_aircraft)) }
                    CollectionKind.TYPE -> TextButton(onClick = { social.open(Route.TypePage(key)) }) { Text(stringResource(R.string.public_page_type)) }
                    CollectionKind.AIRPORT -> airportId?.let { id -> TextButton(onClick = { social.open(Route.AirportPage(id)) }) { Text(stringResource(R.string.public_page_airport)) } }
                }
            }
        }
        item { Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { CollectionSortMenu(app) } }
        items(shown, key = { it.id }) { checkIn -> EntryCheckInRow(checkIn) { social.open(Route.CheckInPage(checkIn.id.toString())) } }
    }
}

@Composable
fun PageHeader(title: String, onBack: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        TextButton(onClick = onBack) { Text("‹ " + stringResource(R.string.back)) }
        Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(start = 8.dp))
    }
}

/** Who sees your check-ins, privacy, and units. */
@Composable
fun SettingsPage(app: WingspotApp, me: String?, social: SocialViewModel) {
    val scope = rememberCoroutineScope()
    var privacy by remember { mutableStateOf<SocialApi.Privacy?>(null) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(me) { if (me != null) try { privacy = app.social.privacy(me) } catch (e: ApiException) { failed = true } }
    fun change(next: SocialApi.Privacy) {
        val before = privacy ?: return
        privacy = next
        scope.launch { try { app.social.setPrivacy(me!!, next) } catch (e: ApiException) { privacy = before; failed = true } }
    }
    Column(Modifier.fillMaxWidth().verticalScrollState(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        PageHeader(stringResource(R.string.settings), social::back)
        if (me != null) {
            SocialSettings(app, me)
            HorizontalDivider()
            NotificationSettings(app, me)
            HorizontalDivider()
            Text(stringResource(R.string.privacy_title), style = MaterialTheme.typography.titleMedium)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.private_profile_switch), Modifier.weight(1f))
                Switch(checked = privacy?.isPrivate ?: false, enabled = privacy != null, onCheckedChange = { change(privacy!!.copy(isPrivate = it)) }, modifier = Modifier.testTag("private-profile"))
            }
            Text(stringResource(R.string.delay_title), style = MaterialTheme.typography.labelLarge)
            for (minutes in listOf(0, 60, 360, 1440)) {
                Row(Modifier.fillMaxWidth().clickable(enabled = privacy != null) { change(privacy!!.copy(postDelayMinutes = minutes)) }, verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(selected = privacy?.postDelayMinutes == minutes, onClick = null, enabled = privacy != null)
                    Text(stringResource(delayTitle(minutes)), Modifier.padding(start = 8.dp))
                }
            }
            Text(stringResource(R.string.privacy_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (failed) Text(stringResource(R.string.privacy_needs_internet), color = MaterialTheme.colorScheme.error)
            HorizontalDivider()
        }
        Text(stringResource(R.string.units_title), style = MaterialTheme.typography.titleMedium)
        for (unit in DistanceUnit.entries) {
            Row(Modifier.fillMaxWidth().clickable { app.prefs.chooseUnit(unit) }, verticalAlignment = Alignment.CenterVertically) {
                RadioButton(selected = app.prefs.unit == unit, onClick = null)
                Text(stringResource(unitTitle(unit)), Modifier.padding(start = 8.dp))
            }
        }
        LegalLinksSection()
        HorizontalDivider()
        Text(stringResource(R.string.about_title), style = MaterialTheme.typography.titleMedium)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.version_label), Modifier.weight(1f))
            Text("${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.testTag("version-line"))
        }
        TextButton(onClick = { social.open(Route.ReleaseNotes) }, modifier = Modifier.testTag("release-notes")) { Text(stringResource(R.string.whats_new)) }
    }
}

/**
 * What changed in each build, newest first, with the installed build marked. Builds newer than the installed one come first, under
 * their own heading: they show what the next update brings. The last list is kept on the phone, so the page opens offline.
 */
@Composable
fun ReleaseNotesPage(app: WingspotApp, social: SocialViewModel) {
    var notes by remember { mutableStateOf(app.prefs.releaseNotesCache?.let(app.releaseNotes::decode).orEmpty()) }
    var loading by remember { mutableStateOf(true) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        try {
            notes = app.releaseNotes.fetch().sortedByDescending { it.build }
            app.prefs.releaseNotesCache = app.releaseNotes.encode(notes)
        } catch (e: Exception) { failed = true }
        loading = false
    }
    val installed = BuildConfig.VERSION_CODE.toLong()
    val groups = groupReleaseNotes(notes, installed)
    val language = java.util.Locale.getDefault().language
    Column(Modifier.fillMaxWidth().verticalScrollState(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        PageHeader(stringResource(R.string.whats_new), social::back)
        if (failed) Text(stringResource(R.string.release_notes_failed), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (groups.newer.isNotEmpty()) {
            Text(stringResource(R.string.release_notes_newer), style = MaterialTheme.typography.titleMedium)
            groups.newer.forEach { ReleaseNoteCard(it, language, installed) }
        }
        groups.installedAndOlder.forEach { ReleaseNoteCard(it, language, installed) }
        if (notes.isEmpty()) {
            if (loading) CircularProgressIndicator(Modifier.align(Alignment.CenterHorizontally))
            else Text(stringResource(R.string.release_notes_empty), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ReleaseNoteCard(note: site.wingspot.core.ReleaseNote, language: String, installed: Long) {
    val (title, lines) = note.text(language)
    Column(Modifier.fillMaxWidth().testTag("release-note-${note.build}"), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("${note.version} (${note.build})", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (note.isBeta) ReleaseTag(stringResource(R.string.tag_beta))
            if (note.build == installed) ReleaseTag(stringResource(R.string.tag_installed))
            Box(Modifier.weight(1f))
            note.day?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
        lines.forEach { Text("•  $it", style = MaterialTheme.typography.bodyMedium) }
        HorizontalDivider(Modifier.padding(top = 8.dp))
    }
}

@Composable
private fun ReleaseTag(text: String) {
    Text(
        text, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.clip(CircleShape).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)).padding(horizontal = 6.dp, vertical = 2.dp),
    )
}

@Composable
private fun Modifier.verticalScrollState(): Modifier = this.verticalScroll(rememberScrollState())

private fun delayTitle(minutes: Int) = when (minutes) {
    0 -> R.string.delay_none; 60 -> R.string.delay_1h; 360 -> R.string.delay_6h; else -> R.string.delay_24h
}

private fun unitTitle(unit: DistanceUnit) = when (unit) {
    DistanceUnit.KILOMETRES -> R.string.unit_km; DistanceUnit.NAUTICAL_MILES -> R.string.unit_nm; DistanceUnit.MILES -> R.string.unit_mi
}

/** Changes your username and name, and your home airport. */
@Composable
fun EditProfilePage(app: WingspotApp, me: String, reference: ReferenceState, social: SocialViewModel) {
    val scope = rememberCoroutineScope()
    var username by remember { mutableStateOf("") }
    var displayName by remember { mutableStateOf("") }
    var home by remember { mutableStateOf<Airport?>(null) }
    var homeChanged by remember { mutableStateOf(false) }
    var loaded by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<Int?>(null) }
    LaunchedEffect(me, reference.database) {
        if (loaded) return@LaunchedEffect
        try {
            app.social.myProfile(me)?.let {
                username = it.username; displayName = it.displayName.orEmpty()
                home = it.homeAirport?.let { id -> reference.database?.airport(id) }
                loaded = true
            }
        } catch (e: ApiException) { error = R.string.error_offline }
    }
    val name = Username.normalized(username)
    Column(Modifier.fillMaxWidth().verticalScrollState(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        PageHeader(stringResource(R.string.edit_profile), social::back)
        ProfilePhotoSection(app, me, displayName.ifBlank { username })
        OutlinedTextField(username, { username = it }, singleLine = true, label = { Text(stringResource(R.string.username_label)) }, modifier = Modifier.fillMaxWidth())
        if (username.isNotBlank() && !Username.isValid(name)) Text(stringResource(R.string.username_rule), style = MaterialTheme.typography.bodySmall)
        OutlinedTextField(displayName, { displayName = it }, singleLine = true, label = { Text(stringResource(R.string.display_name_label)) }, modifier = Modifier.fillMaxWidth())
        Text(stringResource(R.string.home_airport), style = MaterialTheme.typography.labelLarge)
        AirportPickerPublic(reference, home) { home = it; homeChanged = true }
        error?.let { Text(stringResource(it), color = MaterialTheme.colorScheme.error) }
        Button(enabled = loaded && Username.isValid(name), modifier = Modifier.fillMaxWidth().testTag("save-profile"), onClick = {
            scope.launch {
                try {
                    app.social.saveProfile(me, name, displayName)
                    if (homeChanged) app.social.setHomeAirport(me, home?.id)
                    social.back()
                } catch (e: ApiException.Failed) { error = if (e.code == "23505") R.string.username_taken else R.string.username_rule }
                catch (e: ApiException) { error = R.string.error_offline }
            }
        }) { Text(stringResource(R.string.save)) }
    }
}


/** The profile image on the edit page: pick a picture or remove the one you have. */
@Composable
private fun ProfilePhotoSection(app: WingspotApp, me: String, name: String) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var current by remember { mutableStateOf<android.graphics.Bitmap?>(null) }
    var changing by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    val changes = Avatars.changes
    LaunchedEffect(me, changes) { current = Avatars.load(me) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            changing = true
            failed = false
            val prepared = Avatars.prepare(context, uri)
            if (prepared == null) {
                failed = true
            } else {
                try {
                    app.social.uploadAvatar(me, prepared.jpeg, BuildConfig.SUPABASE_URL)
                    Avatars.changed(me, prepared.preview)
                } catch (e: ApiException) { failed = true }
            }
            changing = false
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionHeader(stringResource(R.string.profile_photo))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Avatar(me, name.ifBlank { "?" }, 72.dp)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                OutlinedButton(
                    enabled = !changing, modifier = Modifier.testTag("choose-profile-photo"),
                    onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                ) { Text(stringResource(if (current == null) R.string.choose_photo else R.string.change_photo)) }
                if (current != null) TextButton(
                    enabled = !changing,
                    onClick = {
                        scope.launch {
                            changing = true
                            failed = false
                            try { app.social.removeAvatar(me); Avatars.changed(me, null) } catch (e: ApiException) { failed = true }
                            changing = false
                        }
                    },
                ) { Text(stringResource(R.string.remove_photo), color = MaterialTheme.colorScheme.error) }
            }
        }
        Text(
            stringResource(if (failed) R.string.profile_photo_failed else R.string.profile_photo_hint),
            style = MaterialTheme.typography.bodySmall, color = if (failed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
