package site.wingspot.app

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import site.wingspot.core.ApiException
import site.wingspot.core.FeedCursor
import site.wingspot.core.FeedItem
import site.wingspot.core.Person
import site.wingspot.core.ReportKind

/** Finds people by username. */
@Composable
fun PeopleTab(app: WingspotApp, model: SocialViewModel, me: String) {
    var text by remember { mutableStateOf("") }
    var results by remember { mutableStateOf(emptyList<Person>()) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(text) {
        delay(300)
        if (text.trim().length < 2) { results = emptyList(); return@LaunchedEffect }
        try { results = app.social.searchPeople(text, me); failed = false } catch (e: ApiException) { failed = true }
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.tab_people), style = MaterialTheme.typography.headlineMedium, modifier = Modifier.padding(top = 16.dp))
        OutlinedTextField(
            value = text, onValueChange = { text = it }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("people-search"),
            label = { Text(stringResource(R.string.find_people)) },
        )
        if (failed) Text(stringResource(R.string.error_unknown), color = MaterialTheme.colorScheme.error)
        else if (text.trim().length >= 2 && results.isEmpty()) Text(stringResource(R.string.nothing_found), color = MaterialTheme.colorScheme.onSurfaceVariant)
        results.forEach { person ->
            Column(Modifier.fillMaxWidth().clickable { model.openPerson(person.id) }.padding(vertical = 8.dp)) {
                Text(person.who, fontWeight = FontWeight.Bold)
                Text("@" + person.username, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** Someone's page: follow, block, report, and the check-ins you may see. */
@Composable
fun PersonPage(app: WingspotApp, model: SocialViewModel, id: String, me: String) {
    val scope = rememberCoroutineScope()
    var person by remember { mutableStateOf<Person?>(null) }
    var notFound by remember { mutableStateOf(false) }
    var following by remember { mutableStateOf(false) }
    var followsYou by remember { mutableStateOf(false) }
    var items by remember { mutableStateOf(emptyList<FeedItem>()) }
    var photos by remember { mutableStateOf(emptyMap<String, List<site.wingspot.core.FeedPhoto>>()) }
    var more by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    var confirmBlock by remember { mutableStateOf(false) }
    var reporting by remember { mutableStateOf(false) }

    suspend fun page(after: FeedCursor?) {
        val got = app.social.personCheckIns(id, after)
        items = if (after == null) got else items + got
        more = got.size >= 30
        photos = photos + runCatching { app.social.photos(got.map { it.id }).groupBy { it.checkInId } }.getOrDefault(emptyMap())
    }

    LaunchedEffect(id) {
        try {
            person = app.social.person(id)
            notFound = person == null
            val (out, inn) = app.social.relations(me)
            following = id in out
            followsYou = id in inn
            page(null)
        } catch (e: ApiException) {
            failed = true
        }
    }

    LazyColumn(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = model::back) { Text("‹ " + stringResource(R.string.back)) }
                Box(Modifier.weight(1f))
                if (person != null && id != me) Box {
                    IconButton(onClick = { menu = true }, modifier = Modifier.size(48.dp)) { Text("⋮", style = MaterialTheme.typography.titleLarge) }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text(stringResource(R.string.block)) }, onClick = { menu = false; confirmBlock = true })
                        DropdownMenuItem(text = { Text(stringResource(R.string.report)) }, onClick = { menu = false; reporting = true })
                    }
                }
            }
        }
        if (notFound) item { Text(stringResource(R.string.person_gone)) }
        person?.let { p ->
            item {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(p.who, style = MaterialTheme.typography.headlineMedium)
                    Text("@" + p.username, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (p.isPrivate) Text(stringResource(R.string.private_profile), style = MaterialTheme.typography.bodySmall)
                    if (followsYou) Text(stringResource(R.string.follows_you), style = MaterialTheme.typography.bodySmall)
                    if (id != me) {
                        val toggle: () -> Unit = {
                            val now = !following
                            following = now
                            scope.launch {
                                try { if (now) app.social.follow(id, me) else app.social.unfollow(id, me); page(null) } catch (e: ApiException) { following = !now }
                            }
                        }
                        if (following) OutlinedButton(onClick = toggle, modifier = Modifier.testTag("follow")) { Text(stringResource(R.string.following)) }
                        else Button(onClick = toggle, modifier = Modifier.testTag("follow")) { Text(stringResource(R.string.follow)) }
                    }
                }
            }
        }
        if (failed) item { Text(stringResource(R.string.error_unknown), color = MaterialTheme.colorScheme.error) }
        else if (person != null && items.isEmpty()) item { Text(stringResource(R.string.no_check_ins_visible), color = MaterialTheme.colorScheme.onSurfaceVariant) }
        items(items, key = { it.id }) { item ->
            FeedCard(item, me, photos[item.id].orEmpty(), onOpen = { model.open(item) }, onSalute = {
                val on = !item.saluted
                items = items.map { if (it.id == item.id) it.copy(saluted = on, salutes = (it.salutes + if (on) 1 else -1).coerceAtLeast(0)) else it }
                scope.launch { try { app.social.setSalute(on, item.id, me) } catch (e: ApiException) { items = items.map { if (it.id == item.id) item else it } } }
            }, onPerson = {})
        }
        if (more) item { TextButton(onClick = { scope.launch { items.lastOrNull()?.let { runCatching { page(FeedCursor(it.occurredAt, it.id)) } } } }) { Text(stringResource(R.string.load_more)) } }
    }

    if (confirmBlock) {
        AlertDialog(
            onDismissRequest = { confirmBlock = false },
            title = { Text(stringResource(R.string.block_title, person?.who.orEmpty())) },
            text = { Text(stringResource(R.string.block_message)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmBlock = false
                    scope.launch { try { app.social.block(id, me); model.refresh(); model.back() } catch (e: ApiException) { failed = true } }
                }) { Text(stringResource(R.string.block), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmBlock = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
    if (reporting) ReportDialog(app, ReportKind.USER, id) { reporting = false }
}
