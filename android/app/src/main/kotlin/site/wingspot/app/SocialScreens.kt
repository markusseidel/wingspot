package site.wingspot.app

import android.graphics.BitmapFactory
import android.text.format.DateUtils
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.time.OffsetDateTime
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import site.wingspot.core.ApiException
import site.wingspot.core.CabinClass
import site.wingspot.core.CheckInComment
import site.wingspot.core.Downloads
import site.wingspot.core.FeedItem
import site.wingspot.core.FeedSort
import site.wingspot.core.FeedPhoto
import site.wingspot.core.Flightradar24
import site.wingspot.core.ReportKind

/** "2 hours ago", from the time the server sent. */
fun relativeTime(iso: String): String = try {
    DateUtils.getRelativeTimeSpanString(OffsetDateTime.parse(iso).toInstant().toEpochMilli(), System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS).toString()
} catch (e: Exception) {
    ""
}

/** A picture from a signed link. Shows nothing until it has loaded, and nothing if it can't. */
@Composable
fun RemoteImage(photo: FeedPhoto, modifier: Modifier = Modifier) {
    val bitmap by produceState<androidx.compose.ui.graphics.ImageBitmap?>(null, photo.url) {
        value = Downloads.bytes(photo.url)?.let { withContext(Dispatchers.Default) { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() } }
    }
    val image = bitmap
    if (image != null) Image(image, contentDescription = stringResource(R.string.photo_of_check_in), modifier = modifier, contentScale = ContentScale.Crop)
    else Box(modifier.height(120.dp)) { CircularProgressIndicator(Modifier.size(24.dp).align(Alignment.Center)) }
}

/** The Feed tab. */
@Composable
fun FeedTab(model: SocialViewModel, me: String, announcements: AnnouncementsViewModel) {
    val state by model.state.collectAsState()
    LaunchedEffect(me) { announcements.refresh(); if (!state.hasLoaded) model.refresh() }
    LazyColumn(Modifier.fillMaxWidth().testTag("feed"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.tab_feed), style = MaterialTheme.typography.headlineMedium, modifier = Modifier.padding(top = 16.dp).weight(1f))
                var menu by remember { mutableStateOf(false) }
                Box {
                    TextButton(onClick = { menu = true }, modifier = Modifier.testTag("feed-sort")) {
                        Text(stringResource(if (model.sort == FeedSort.CREATED) R.string.sort_checked_in else R.string.sort_flight_date) + " ▾")
                    }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text(stringResource(R.string.sort_checked_in)) }, onClick = { menu = false; model.chooseSort(FeedSort.CREATED) })
                        DropdownMenuItem(text = { Text(stringResource(R.string.sort_flight_date)) }, onClick = { menu = false; model.chooseSort(FeedSort.OCCURRED) })
                    }
                }
            }
        }
        item { AnnouncementCards(announcements) }
        if (state.failed) item { Text(stringResource(R.string.feed_failed), color = MaterialTheme.colorScheme.error) }
        if (state.hasLoaded && state.items.isEmpty() && !state.failed) item { Text(stringResource(R.string.feed_empty)) }
        items(state.items, key = { it.id }) { item ->
            FeedCard(item, me, state.photos[item.id].orEmpty(), onOpen = { model.open(item) }, onSalute = { model.toggleSalute(item.id) }, onPerson = { model.openPerson(item.userId) }, tags = state.tags[item.id].orEmpty())
            if (item.id == state.items.lastOrNull()?.id) LaunchedEffect(item.id) { model.loadMore() }
        }
        item {
            if (state.isLoading) CircularProgressIndicator(Modifier.padding(16.dp))
            else TextButton(onClick = { announcements.refresh(); model.refresh() }) { Text(stringResource(R.string.refresh)) }
        }
    }
}

/** One check-in in a list: who, what, the first photo, and salute and comments. The whole card opens the check-in page. */
@Composable
fun FeedCard(
    item: FeedItem, me: String, photos: List<FeedPhoto>, onOpen: () -> Unit, onSalute: () -> Unit, onPerson: () -> Unit,
    tags: List<site.wingspot.core.Person> = emptyList(),
) {
    Card(Modifier.fillMaxWidth().clickable(onClick = onOpen)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Avatar(item.userId, item.who, 28.dp)
                if (item.userId == me) {
                    Text(stringResource(R.string.you), fontWeight = FontWeight.Bold)
                } else {
                    Text(item.who, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary, modifier = Modifier.clickable(onClick = onPerson).padding(vertical = 8.dp))
                }
                Box(Modifier.weight(1f))
                Text(relativeTime(item.occurredAt), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            KindAndTitle(item)
            if (tags.isNotEmpty()) Text(stringResource(R.string.with_names, tags.joinToString(", ") { it.who }), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            photos.firstOrNull()?.let { RemoteImage(it, Modifier.fillMaxWidth().height(200.dp).clip(MaterialTheme.shapes.medium)) }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SaluteButton(item, onSalute)
                TextButton(onClick = onOpen) { Text(stringResource(R.string.comments_count, item.comments)) }
            }
        }
    }
}

@Composable
fun KindAndTitle(item: FeedItem, model: SocialViewModel? = null) {
    Text(
        stringResource(when (item.kind) { "flown" -> R.string.flown_title; "airport" -> R.string.airport_title; else -> R.string.spotted_title }),
        style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    // The title opens the page of the registration, the type or the airport.
    val target: Route? = when {
        item.kind == "airport" && item.airportId != null -> Route.AirportPage(item.airportId!!)
        item.kind == "spotted" && item.registration != null -> Route.RegistrationPage(item.registration!!)
        item.kind == "spotted" && item.typeIcao != null -> Route.TypePage(item.typeIcao!!)
        else -> null
    }
    Text(
        item.title, style = MaterialTheme.typography.titleLarge, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold,
        color = if (target != null && model != null) MaterialTheme.colorScheme.primary else androidx.compose.ui.graphics.Color.Unspecified,
        modifier = if (target != null && model != null) Modifier.clickable { model.open(target) }.padding(vertical = 4.dp) else Modifier,
    )
    val unit = (androidx.compose.ui.platform.LocalContext.current.applicationContext as WingspotApp).prefs.unit
    val details = listOfNotNull(item.typeName, item.flightNumber, item.distanceKm?.let { unit.format(it) }).joinToString(" · ")
    if (details.isNotBlank()) Text(details, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun SaluteButton(item: FeedItem, onSalute: () -> Unit) {
    val label = stringResource(R.string.salute_count, item.salutes)
    if (item.saluted) FilledTonalButton(onClick = onSalute) { Text(label) } else OutlinedButton(onClick = onSalute) { Text(label) }
}

/** One check-in on its own page: who, when and what, the photos, salute, and the comments with a field to write a new one. */
@Composable
fun CheckInPage(app: WingspotApp, model: SocialViewModel, checkIn: CheckInViewModel, id: String, me: String) {
    val scope = rememberCoroutineScope()
    val feed by model.state.collectAsState()
    var loaded by remember { mutableStateOf<FeedItem?>(null) }
    var gone by remember { mutableStateOf(false) }
    var photos by remember { mutableStateOf(emptyList<FeedPhoto>()) }
    var comments by remember { mutableStateOf(emptyList<CheckInComment>()) }
    var commentsFailed by remember { mutableStateOf(false) }
    var text by remember { mutableStateOf("") }
    val focusManager = LocalFocusManager.current
    var problem by remember { mutableStateOf<Int?>(null) }
    var menu by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var pickVisibility by remember { mutableStateOf(false) }
    var reporting by remember { mutableStateOf<Pair<ReportKind, String>?>(null) }
    var localFlight by remember { mutableStateOf(false) }
    var viewing by remember { mutableStateOf<FeedPhoto?>(null) }
    var tags by remember { mutableStateOf(feed.tags[id].orEmpty()) }
    var confirmLeave by remember { mutableStateOf(false) }
    val mine by checkIn.state.collectAsState()

    // The list's copy has the live counts. The copy loaded by id has the airports and your own cabin and seat.
    val fromList = feed.items.firstOrNull { it.id == id } ?: model.opened[id]
    val shown = (loaded ?: fromList)?.let { l -> fromList?.let { l.copy(salutes = it.salutes, comments = it.comments, saluted = it.saluted) } ?: l }

    LaunchedEffect(id) {
        try {
            loaded = app.social.checkIn(id)
            gone = loaded == null && fromList == null
            photos = feed.photos[id] ?: app.social.photos(listOf(id))
            tags = model.reloadTags(id)
            comments = app.social.comments(id)
            model.setCommentCount(id, comments.size)
        } catch (e: ApiException) {
            commentsFailed = true
        }
        localFlight = runCatching { app.checkIns.find(UUID.fromString(id)) != null }.getOrDefault(false)
    }

    if (pickVisibility) VisibilityDialog(app, id, onClose = { pickVisibility = false })
    LazyColumn(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = model::back) { Text("‹ " + stringResource(R.string.back)) }
                Box(Modifier.weight(1f))
                if (shown != null) Box {
                    IconButton(onClick = { menu = true }, modifier = Modifier.size(48.dp).testTag("page-more")) { Text("⋮", style = MaterialTheme.typography.titleLarge) }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        if (shown.userId == me) {
                            if (localFlight) {
                                DropdownMenuItem(text = { Text(stringResource(R.string.edit_details)) }, onClick = { menu = false; checkIn.edit(UUID.fromString(id)) })
                            }
                            DropdownMenuItem(text = { Text(stringResource(R.string.who_can_see)) }, onClick = { menu = false; pickVisibility = true })
                            DropdownMenuItem(text = { Text(stringResource(R.string.delete)) }, onClick = { menu = false; confirmDelete = true })
                        } else {
                            if (tags.any { it.id == me }) DropdownMenuItem(text = { Text(stringResource(R.string.remove_me_tag)) }, onClick = { menu = false; confirmLeave = true })
                            DropdownMenuItem(text = { Text(stringResource(R.string.report)) }, onClick = { menu = false; reporting = ReportKind.CHECKIN to id })
                        }
                    }
                }
            }
        }
        if (gone) item { Text(stringResource(R.string.check_in_gone)) }
        if (shown == null && !gone) item { CircularProgressIndicator() }
        if (shown != null) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (shown.userId == me) Text(stringResource(R.string.you), fontWeight = FontWeight.Bold)
                    else Text(shown.who, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary, modifier = Modifier.clickable { model.openPerson(shown.userId) }.padding(vertical = 8.dp))
                    KindAndTitle(shown, model)
                    if (shown.kind == "flown") Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        shown.originId?.let { o -> OutlinedButton(onClick = { model.open(Route.AirportPage(o)) }) { Text(stringResource(R.string.from_airport, shown.originCode ?: "?")) } }
                        shown.destinationId?.let { d -> OutlinedButton(onClick = { model.open(Route.AirportPage(d)) }) { Text(stringResource(R.string.to_airport, shown.destinationCode ?: "?")) } }
                    }
                    Text(fullTime(shown.occurredAt), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    val unit = app.prefs.unit
                    shown.flightNumber?.let { InfoRow(stringResource(R.string.flight_label), it) }
                    shown.registration?.let { r -> InfoRow(stringResource(R.string.aircraft_label), r, if (shown.kind == "spotted") null else ({ model.open(Route.RegistrationPage(r)) })) }
                    shown.typeIcao?.let { t -> InfoRow(stringResource(R.string.type_label), shown.typeName ?: t) { model.open(Route.TypePage(t)) } }
                    if (shown.kind == "spotted") shown.airportId?.let { a -> InfoRow(stringResource(R.string.airport_label), shown.airportCode ?: "?") { model.open(Route.AirportPage(a)) } }
                    if (shown.kind == "flown") {
                        shown.cabin?.let { c -> CabinClass.fromWire(c)?.let { InfoRow(stringResource(R.string.cabin_label), stringResource(cabinTitle(it))) } }
                        shown.seat?.let { InfoRow(stringResource(R.string.seat_row_label), it) }
                        shown.distanceKm?.let { InfoRow(stringResource(R.string.distance_label), unit.format(it)) }
                    }
                }
            }
            items(photos, key = { it.id }) { photo ->
                Box {
                    RemoteImage(photo, Modifier.fillMaxWidth().clip(MaterialTheme.shapes.medium).clickable { viewing = photo })
                    if (shown.userId != me) TextButton(onClick = { reporting = ReportKind.PHOTO to photo.id }, modifier = Modifier.align(Alignment.TopEnd)) { Text(stringResource(R.string.report)) }
                }
            }
            if (tags.isNotEmpty()) item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.with_label), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column {
                            tags.forEachIndexed { index, person ->
                                if (index > 0) HorizontalDivider(Modifier.padding(start = 64.dp))
                                val isMe = person.id == me
                                Row(
                                    Modifier.fillMaxWidth().then(if (isMe) Modifier else Modifier.clickable { model.openPerson(person.id) }).padding(horizontal = 12.dp, vertical = 10.dp),
                                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                                ) {
                                    val name = if (isMe) stringResource(R.string.you) else person.who
                                    Avatar(person.id, name, 40.dp)
                                    Text(name, style = MaterialTheme.typography.bodyLarge)
                                }
                            }
                        }
                    }
                }
            }
            item { SaluteButton(shown) { model.toggleSalute(id) } }
            // A friend's flight or airport visit that you are tagged on can be added to your own logbook, once.
            if (shown.userId != me && tags.any { it.id == me } && (shown.kind == "flown" || shown.kind == "airport")) item {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    if (mine.all.any { it.sourceId?.toString() == id }) {
                        Text(stringResource(R.string.in_my_logbook), color = MaterialTheme.colorScheme.primary)
                    } else {
                        OutlinedButton(onClick = { checkIn.addFromFriend(shown) }, modifier = Modifier.testTag("add-to-logbook")) { Text(stringResource(R.string.add_to_logbook)) }
                        Text(stringResource(R.string.add_to_logbook_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            val flightPage = if (shown.userId == me && shown.kind == "flown") shown.flightNumber?.let(Flightradar24::flight) else null
            val aircraftPage = if (shown.userId == me && shown.kind == "flown") shown.registration?.let(Flightradar24::aircraft) else null
            if (flightPage != null || aircraftPage != null) item {
                val uri = androidx.compose.ui.platform.LocalUriHandler.current
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    flightPage?.let { TextButton(onClick = { uri.openUri(it) }) { Text(stringResource(R.string.lookup_flight)) } }
                    aircraftPage?.let { TextButton(onClick = { uri.openUri(it) }) { Text(stringResource(R.string.lookup_aircraft)) } }
                    Text(stringResource(R.string.lookup_footer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 8.dp)) {
                    Text(stringResource(R.string.comments_title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    if (comments.isNotEmpty()) Text(comments.size.toString(), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (commentsFailed) item { Text(stringResource(R.string.comments_failed), color = MaterialTheme.colorScheme.error) }
            else if (comments.isEmpty()) item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(painterResource(R.drawable.ic_comments), contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(48.dp))
                        Text(stringResource(R.string.no_comments), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            items(comments, key = { it.id }) { comment ->
                var open by remember { mutableStateOf(false) }
                Card(modifier = Modifier.fillMaxWidth()) {
                    Row(Modifier.padding(start = 12.dp, top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Box(Modifier.padding(top = 4.dp)) { Avatar(comment.userId, comment.who, 40.dp) }
                        Column(Modifier.weight(1f).padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Row(horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                                Text(comment.who, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                                Text(relativeTime(comment.createdAt), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Text(comment.body, style = MaterialTheme.typography.bodyLarge)
                        }
                        Box {
                            IconButton(onClick = { open = true }, modifier = Modifier.size(48.dp)) { Text("⋮", style = MaterialTheme.typography.titleLarge) }
                            DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                                if (comment.userId == me || shown.userId == me) {
                                    DropdownMenuItem(text = { Text(stringResource(R.string.delete)) }, onClick = {
                                        open = false
                                        scope.launch {
                                            try { app.social.deleteComment(comment.id); comments = comments.filterNot { it.id == comment.id }; model.setCommentCount(id, comments.size) }
                                            catch (e: ApiException) { problem = R.string.error_unknown }
                                        }
                                    })
                                }
                                if (comment.userId != me) DropdownMenuItem(text = { Text(stringResource(R.string.report)) }, onClick = { open = false; reporting = ReportKind.COMMENT to comment.id })
                            }
                        }
                    }
                }
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        OutlinedTextField(
                            value = text, onValueChange = { text = it }, modifier = Modifier.weight(1f).testTag("comment"),
                            placeholder = { Text(stringResource(R.string.write_comment)) },
                            maxLines = 5,
                        )
                        Button(
                            enabled = text.isNotBlank(), modifier = Modifier.size(52.dp).testTag("send-comment"),
                            shape = CircleShape, contentPadding = PaddingValues(0.dp),
                            onClick = {
                                scope.launch {
                                    try {
                                        val added = app.social.addComment(text.trim(), id, me)
                                        comments = comments + added
                                        text = ""
                                        problem = null
                                        focusManager.clearFocus()
                                        model.setCommentCount(id, comments.size)
                                    } catch (e: ApiException.Failed) {
                                        problem = if (e.code == "23514") R.string.comment_refused else R.string.error_unknown
                                    } catch (e: ApiException) {
                                        problem = R.string.error_offline
                                    }
                                }
                            },
                        ) { Text("↑", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold) }
                    }
                    problem?.let { Text(stringResource(it), color = MaterialTheme.colorScheme.error) }
                }
            }
        }
    }

    if (confirmLeave) {
        AlertDialog(
            onDismissRequest = { confirmLeave = false },
            title = { Text(stringResource(R.string.remove_me_title)) },
            text = { Text(stringResource(R.string.remove_me_message)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmLeave = false
                    scope.launch {
                        try {
                            app.social.removeMyTag(id)
                            tags = model.reloadTags(id)
                            // A private check-in can no longer be seen, so the page goes.
                            if (app.social.checkIn(id) == null) { model.remove(id); model.back() }
                        } catch (e: ApiException) { problem = R.string.error_offline }
                    }
                }) { Text(stringResource(R.string.remove_me)) }
            },
            dismissButton = { TextButton(onClick = { confirmLeave = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text(stringResource(R.string.delete_title)) },
            text = { Text(stringResource(R.string.delete_message)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    scope.launch {
                        if (app.outbox.delete(UUID.fromString(id))) { model.remove(id); checkIn.reload(); model.back() } else problem = R.string.delete_failed
                    }
                }) { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
    reporting?.let { (kind, target) -> ReportDialog(app, kind, target) { reporting = null } }
    viewing?.let { start -> PhotoViewer(photos, start) { viewing = null } }
}

/** A label and its value; with [onClick] the value is a link to the page of the aircraft, type or airport. */
@Composable
private fun InfoRow(label: String, value: String, onClick: (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier).padding(vertical = 4.dp)) {
        Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
        Text(value, color = if (onClick != null) MaterialTheme.colorScheme.primary else androidx.compose.ui.graphics.Color.Unspecified)
    }
}

/** The day and time of a check-in, in the phone's language. */
fun fullTime(iso: String): String = try {
    java.time.format.DateTimeFormatter.ofLocalizedDateTime(java.time.format.FormatStyle.MEDIUM, java.time.format.FormatStyle.SHORT)
        .format(OffsetDateTime.parse(iso).atZoneSameInstant(java.time.ZoneId.systemDefault()))
} catch (e: Exception) {
    ""
}

/** The photos of a check-in full screen, swiping between them. A tap on the close button leaves. */
@Composable
private fun PhotoViewer(photos: List<FeedPhoto>, start: FeedPhoto, onClose: () -> Unit) {
    androidx.compose.ui.window.Dialog(onDismissRequest = onClose, properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false)) {
        val pager = androidx.compose.foundation.pager.rememberPagerState(initialPage = photos.indexOfFirst { it.id == start.id }.coerceAtLeast(0)) { photos.size }
        Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.Black)) {
            androidx.compose.foundation.pager.HorizontalPager(pager) { page ->
                RemoteImageFit(photos[page], Modifier.fillMaxSize())
            }
            TextButton(onClick = onClose, modifier = Modifier.align(Alignment.TopEnd).padding(8.dp)) { Text(stringResource(R.string.close), color = androidx.compose.ui.graphics.Color.White) }
        }
    }
}

/** Like [RemoteImage] but shows the whole picture. */
@Composable
private fun RemoteImageFit(photo: FeedPhoto, modifier: Modifier = Modifier) {
    val bitmap by produceState<androidx.compose.ui.graphics.ImageBitmap?>(null, photo.url) {
        value = Downloads.bytes(photo.url)?.let { withContext(Dispatchers.Default) { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() } }
    }
    val image = bitmap
    if (image != null) Image(image, contentDescription = stringResource(R.string.photo_of_check_in), modifier = modifier, contentScale = ContentScale.Fit)
    else Box(modifier) { CircularProgressIndicator(Modifier.size(24.dp).align(Alignment.Center)) }
}

/** Asks why, then sends the report. The server stores the reason as free text. */
@Composable
fun ReportDialog(app: WingspotApp, kind: ReportKind, target: String, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    val reasons = listOf("spam" to R.string.reason_spam, "offensive" to R.string.reason_offensive, "privacy" to R.string.reason_privacy, "other" to R.string.reason_other)
    var chosen by remember { mutableStateOf("spam") }
    var sent by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text(stringResource(if (sent) R.string.report_sent_title else R.string.report_title)) },
        text = {
            if (sent) Text(stringResource(R.string.report_sent))
            else Column {
                for ((key, label) in reasons) Row(Modifier.fillMaxWidth().clickable { chosen = key }, verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(selected = chosen == key, onClick = { chosen = key }); Text(stringResource(label))
                }
                if (failed) Text(stringResource(R.string.error_unknown), color = MaterialTheme.colorScheme.error)
            }
        },
        confirmButton = {
            if (sent) TextButton(onClick = onClose) { Text(stringResource(R.string.done)) }
            else TextButton(onClick = { scope.launch { try { app.social.report(kind, target, chosen); sent = true } catch (e: ApiException) { failed = true } } }) { Text(stringResource(R.string.send)) }
        },
        dismissButton = { if (!sent) TextButton(onClick = onClose) { Text(stringResource(R.string.cancel)) } },
    )
}
