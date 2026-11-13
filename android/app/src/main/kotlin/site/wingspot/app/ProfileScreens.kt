package site.wingspot.app

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
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
import site.wingspot.core.CollectionEntry
import site.wingspot.core.Collections
import site.wingspot.core.DistanceUnit
import site.wingspot.core.LocalCheckIn
import site.wingspot.core.SocialApi
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
                    Text(stringResource(R.string.profile_signed_out))
                    val context = LocalContext.current
                    SignInForm(state.isWorking, model::sendLink, model::signInWithPassword,
                        if (GoogleSignIn.isAvailable) ({ scope.launch { GoogleSignIn.idToken(context)?.let { (token, nonce) -> model.signInWithGoogle(token, nonce) } ?: model.googleFailed() } }) else null)
                }
            }
            state.error?.let { Text(stringResource(it), color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("error")) }
            if (stats.checkIns > 0) StatsCard(stats)
            OutlinedButton(onClick = { social.open(Route.Collections) }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.collections)) }
        } else {
            progress.progress?.let { LevelHeader(it) }
            StatsCard(stats)
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Detail(stringResource(R.string.username_label), mine?.username?.let { "@$it" } ?: "…")
                    mine?.displayName?.let { Detail(stringResource(R.string.name_label), it) }
                    home?.let { Detail(stringResource(R.string.home_airport), "${it.code} · ${it.name}") }
                    Detail(stringResource(R.string.signed_in_as_short), session.user.email ?: session.user.id)
                }
            }
            for ((label, route) in listOf(R.string.collections to Route.Collections, R.string.edit_profile to Route.EditProfile, R.string.settings to Route.Settings)) {
                OutlinedButton(onClick = { social.open(route) }, modifier = Modifier.fillMaxWidth().testTag("profile-$label")) { Text(stringResource(label)) }
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
            OutlinedButton(onClick = { scope.launch { Push.unregister(app); social.clear(); badges.begin(null); model.signOut() } }, modifier = Modifier.fillMaxWidth().testTag("sign-out")) { Text(stringResource(R.string.sign_out)) }
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
private fun StatsCard(stats: CheckInStats) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Detail(stringResource(R.string.stat_check_ins), stats.checkIns.toString())
            Detail(stringResource(R.string.stat_sightings), stats.sightings.toString())
            Detail(stringResource(R.string.stat_flights), stats.flights.toString())
            Detail(stringResource(R.string.stat_airport_visits), stats.airportVisits.toString())
            Detail(stringResource(R.string.stat_aircraft), stats.aircraft.toString())
            Detail(stringResource(R.string.stat_types), stats.types.toString())
            Detail(stringResource(R.string.stat_airports), stats.airports.toString())
        }
    }
}

/** What has been seen: aircraft, types and airports, from the check-ins on this phone. */
@Composable
fun CollectionsPage(local: List<LocalCheckIn>, social: SocialViewModel) {
    var tab by remember { mutableStateOf(0) }
    val lists = Collections.of(local)
    val entries: List<CollectionEntry> = when (tab) { 0 -> lists.aircraft; 1 -> lists.types; else -> lists.airports }
    LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item { PageHeader(stringResource(R.string.collections), social::back) }
        item { OutlinedButton(onClick = { social.open(Route.AirportsMap) }, modifier = Modifier.fillMaxWidth().testTag("airports-map")) { Text(stringResource(R.string.airports_map)) } }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for ((i, label) in listOf(R.string.tab_aircraft, R.string.tab_types, R.string.airports).withIndex()) {
                    FilterChip(selected = tab == i, onClick = { tab = i }, label = { Text(stringResource(label)) })
                }
            }
        }
        if (entries.isEmpty()) item { Text(stringResource(R.string.nothing_here_yet), color = MaterialTheme.colorScheme.onSurfaceVariant) }
        items(entries, key = { it.id }) { entry ->
            Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(entry.title, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.titleMedium)
                    Text(
                        stringResource(R.string.last_seen, DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(entry.lastSeen.atZone(ZoneId.systemDefault()))),
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text("×${entry.count}", style = MaterialTheme.typography.titleMedium)
            }
        }
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
    }
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
