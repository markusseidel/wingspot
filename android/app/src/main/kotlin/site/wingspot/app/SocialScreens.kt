package site.wingspot.app

import android.graphics.BitmapFactory
import android.text.format.DateUtils
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.withLink
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.layout.defaultMinSize
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
import androidx.compose.runtime.DisposableEffect
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
import site.wingspot.core.CommentText
import site.wingspot.core.SocialApi
import site.wingspot.core.Downloads
import site.wingspot.core.FeedItem
import site.wingspot.core.FeedSort
import site.wingspot.core.FeedPhoto
import site.wingspot.core.Flightradar24
import site.wingspot.core.ReportKind

/** "2 hours ago", from the time the server sent. */
/**
 * The date on a feed entry: relative for the last 7 days, then a short date with the month abbreviated, with the year
 * only when it isn't the current one ([site.wingspot.core.FeedDateRule]). The same rule as iOS.
 */
fun feedDate(iso: String): String = try {
    val then = OffsetDateTime.parse(iso).toInstant()
    val now = java.time.Instant.now()
    when (site.wingspot.core.FeedDateRule.style(then, now)) {
        site.wingspot.core.FeedDateStyle.RELATIVE -> relativeTime(iso)
        site.wingspot.core.FeedDateStyle.DATE -> android.icu.text.DateFormat.getInstanceForSkeleton("dMMM").format(java.util.Date.from(then))
        site.wingspot.core.FeedDateStyle.DATE_WITH_YEAR -> android.icu.text.DateFormat.getInstanceForSkeleton("dMMMy").format(java.util.Date.from(then))
    }
} catch (e: Exception) {
    ""
}

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
fun FeedTab(model: SocialViewModel, me: String, announcements: AnnouncementsViewModel, checkIn: CheckInViewModel? = null) {
    val state by model.state.collectAsState()
    LaunchedEffect(me) { announcements.refresh(); if (!state.hasLoaded) model.refresh() }
    // The dot on the bell: when this tab opens, when the app comes back, and when a page above it closes.
    val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current
    DisposableEffect(lifecycle) {
        val watcher = androidx.lifecycle.LifecycleEventObserver { _, event -> if (event == androidx.lifecycle.Lifecycle.Event.ON_RESUME) model.refreshUnread() }
        lifecycle.lifecycle.addObserver(watcher)
        onDispose { lifecycle.lifecycle.removeObserver(watcher) }
    }
    LaunchedEffect(me) { model.refreshUnread() }
    LazyColumn(Modifier.fillMaxWidth().testTag("feed"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.tab_feed), style = MaterialTheme.typography.headlineMedium, modifier = Modifier.padding(top = 16.dp).weight(1f))
                Box {
                    IconButton(onClick = { model.open(Route.Inbox) }, modifier = Modifier.size(48.dp).testTag("open-inbox")) {
                        Icon(
                            painterResource(R.drawable.ic_bell),
                            contentDescription = stringResource(if (model.unread > 0) R.string.activity_open_new else R.string.activity_open),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                    if (model.unread > 0) Box(Modifier.align(Alignment.TopEnd).padding(top = 10.dp, end = 10.dp).size(10.dp).background(MaterialTheme.colorScheme.error, CircleShape).testTag("inbox-dot"))
                }
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
            FeedCard(item, me, state.photos[item.id].orEmpty(), onOpen = { model.open(item) }, onSalute = { model.toggleSalute(item.id) }, onPerson = { model.openPerson(item.userId) }, tags = state.tags[item.id].orEmpty(), badges = state.badges[item.id].orEmpty(), onEdit = checkIn?.let { vm -> { id -> vm.edit(id) } }, onRemoved = { model.remove(it) })
            if (item.id == state.items.lastOrNull()?.id) LaunchedEffect(item.id) { model.loadMore() }
        }
        item {
            if (state.isLoading) CircularProgressIndicator(Modifier.padding(16.dp))
            else TextButton(onClick = { announcements.refresh(); model.refresh() }) { Text(stringResource(R.string.refresh)) }
        }
    }
}

/**
 * One check-in in a list, as a plain row with a divider (docs/FEED-ENTRY-SPEC.md): who and when, what kind, the main
 * line, details, badges, photos, and salute and comments as small icons with counts. The whole entry opens the check-in page.
 */
@Composable
fun FeedCard(
    item: FeedItem, me: String, photos: List<FeedPhoto>, onOpen: () -> Unit, onSalute: () -> Unit, onPerson: () -> Unit,
    tags: List<site.wingspot.core.Person> = emptyList(),
    badges: List<site.wingspot.core.SocialApi.FeedBadge> = emptyList(),
    /** Starts the edit of one of your own check-ins that is on this phone. Null where the list can't edit. */
    onEdit: ((UUID) -> Unit)? = null,
    /** Called after one of your own check-ins was deleted from the menu, so the list can drop it. */
    onRemoved: (String) -> Unit = {},
) {
    val app = androidx.compose.ui.platform.LocalContext.current.applicationContext as WingspotApp
    val scope = rememberCoroutineScope()
    var confirmDelete by remember { mutableStateOf(false) }
    var reporting by remember { mutableStateOf(false) }
    var failedDelete by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().clickable(onClick = onOpen)) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Avatar(item.userId, item.who, 28.dp)
                // Names are plain text; the accent colour is only for actions.
                if (item.userId == me) {
                    Text(stringResource(R.string.you), fontWeight = FontWeight.Bold)
                } else {
                    Text(item.who, fontWeight = FontWeight.Bold, modifier = Modifier.clickable(onClick = onPerson).padding(vertical = 8.dp))
                }
                Box(Modifier.weight(1f))
                Text(feedDate(item.occurredAt), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                FeedCardMenu(
                    own = item.userId == me, id = item.id, onEdit = onEdit,
                    onDelete = { confirmDelete = true }, onReport = { reporting = true },
                )
            }
            KindAndTitle(item)
            if (tags.isNotEmpty()) Text(stringResource(R.string.with_names, tags.joinToString(", ") { it.who }), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (badges.isNotEmpty()) FeedBadgesLine(badges)
            if (photos.isNotEmpty()) PhotoCarousel(photos)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                CountAction(
                    icon = if (item.saluted) R.drawable.ic_glyph_salute_filled else R.drawable.ic_glyph_salute,
                    count = item.salutes, description = stringResource(R.string.salute_count, item.salutes), tag = "salute", onClick = onSalute,
                )
                CountAction(
                    icon = R.drawable.ic_comments, count = item.comments, description = stringResource(R.string.comments_count, item.comments),
                    tag = "comments", onClick = onOpen,
                )
            }
        }
        HorizontalDivider(Modifier.padding(top = 12.dp))
    }
    if (confirmDelete) DeleteCheckInDialog(
        onConfirm = {
            confirmDelete = false
            scope.launch {
                if (app.outbox.delete(UUID.fromString(item.id))) { onRemoved(item.id); app.uploads.tryEmit(Unit) } else failedDelete = true
            }
        },
        onDismiss = { confirmDelete = false },
    )
    if (failedDelete) AlertDialog(
        onDismissRequest = { failedDelete = false },
        text = { Text(stringResource(R.string.delete_failed)) },
        confirmButton = { TextButton(onClick = { failedDelete = false }) { Text(stringResource(R.string.ok)) } },
    )
    if (reporting) ReportDialog(app, ReportKind.CHECKIN, item.id) { reporting = false }
}

/**
 * The ⋯ menu on an entry (docs/FEED-ENTRY-SPEC.md): Edit details and Delete for your own check-ins (Edit only for one
 * that is on this phone and where the list can edit), Report for other people's.
 */
@Composable
private fun FeedCardMenu(own: Boolean, id: String, onEdit: ((UUID) -> Unit)?, onDelete: () -> Unit, onReport: () -> Unit) {
    val app = androidx.compose.ui.platform.LocalContext.current.applicationContext as WingspotApp
    var open by remember { mutableStateOf(false) }
    // Whether the check-in is on this phone, so it can be edited. Only looked up for your own entries.
    val onThisPhone by produceState(false, id, own, onEdit) {
        value = own && onEdit != null && runCatching { app.checkIns.find(UUID.fromString(id)) != null }.getOrDefault(false)
    }
    Box {
        IconButton(onClick = { open = true }, modifier = Modifier.size(48.dp).testTag("entry-more")) {
            Icon(painterResource(R.drawable.ic_glyph_more), contentDescription = stringResource(R.string.more), tint = MaterialTheme.colorScheme.primary)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            if (own) {
                if (onThisPhone) DropdownMenuItem(text = { Text(stringResource(R.string.edit_details)) }, onClick = { open = false; onEdit?.invoke(UUID.fromString(id)) })
                DropdownMenuItem(text = { Text(stringResource(R.string.delete)) }, onClick = { open = false; onDelete() })
            } else {
                DropdownMenuItem(text = { Text(stringResource(R.string.report)) }, onClick = { open = false; onReport() })
            }
        }
    }
}

/** Asks before a check-in is deleted. The same dialog on the entry's menu and on the check-in page. */
@Composable
fun DeleteCheckInDialog(onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.delete_title)) },
        text = { Text(stringResource(R.string.delete_message)) },
        confirmButton = { TextButton(onClick = onConfirm) { Text(stringResource(R.string.delete), color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

/** A small icon with a count in the accent colour. The touch area is still 48 dp high. */
@Composable
private fun CountAction(icon: Int, count: Int, description: String, tag: String, onClick: () -> Unit) {
    Row(
        Modifier.defaultMinSize(minWidth = 48.dp, minHeight = 48.dp).clip(MaterialTheme.shapes.small).clickable(onClick = onClick).padding(horizontal = 8.dp).testTag(tag).semantics { contentDescription = description },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(painterResource(icon), contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
        Text(count.toString(), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary)
    }
}

/**
 * One photo is shown full width. Several are a carousel: one per page, swipe sideways, a row of dots below. Every page
 * has the same height, so the list does not jump.
 */
@Composable
private fun PhotoCarousel(photos: List<FeedPhoto>) {
    val shape = RoundedCornerShape(10.dp)
    if (photos.size == 1) {
        RemoteImage(photos.first(), Modifier.fillMaxWidth().height(200.dp).clip(shape))
        return
    }
    val pager = rememberPagerState { photos.size }
    HorizontalPager(pager, Modifier.fillMaxWidth().height(200.dp).testTag("photo-carousel"), pageSpacing = 8.dp) { page ->
        RemoteImage(photos[page], Modifier.fillMaxSize().clip(shape))
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
        repeat(photos.size) { index ->
            Box(
                Modifier.padding(horizontal = 3.dp).size(6.dp).clip(CircleShape)
                    .background(if (index == pager.currentPage) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)),
            )
        }
    }
}

@Composable
fun KindAndTitle(item: FeedItem, model: SocialViewModel? = null) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Icon(
            painterResource(when (item.kind) { "flown" -> R.drawable.ic_glyph_plane; "airport" -> R.drawable.ic_glyph_building; else -> R.drawable.ic_glyph_binoculars }),
            contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(16.dp),
        )
        Text(
            stringResource(when (item.kind) { "flown" -> R.string.flown_title; "airport" -> R.string.airport_title; else -> R.string.spotted_title }),
            style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
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
    // The same order as on iOS: a flight shows its number, then the registration (the type name without one), then the distance.
    val details = when (item.kind) {
        "airport" -> emptyList()
        "flown" -> listOfNotNull(item.flightNumber, item.registration ?: item.typeName, item.distanceKm?.let { unit.format(it) })
        else -> listOfNotNull(item.typeName ?: item.registration?.let { item.typeIcao }, item.airportCode)
    }.joinToString(" · ")
    if (details.isNotBlank()) Text(details, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun SaluteButton(item: FeedItem, onSalute: () -> Unit) {
    val label = stringResource(R.string.salute_count, item.salutes)
    // The hand with the count, as on iOS; filled once you saluted.
    val content: @Composable () -> Unit = {
        Icon(
            painterResource(if (item.saluted) R.drawable.ic_glyph_salute_filled else R.drawable.ic_glyph_salute),
            contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp),
        )
        Text(item.salutes.toString(), Modifier.padding(start = 8.dp), color = MaterialTheme.colorScheme.primary)
    }
    val modifier = Modifier.testTag("salute-page").semantics { contentDescription = label }
    if (item.saluted) FilledTonalButton(onClick = onSalute, modifier = modifier) { content() } else OutlinedButton(onClick = onSalute, modifier = modifier) { content() }
}

/** The saved route of a flight, as the flight page shows it: the numbers and the simplified line for the map. */
private data class FlownTrack(val route: site.wingspot.core.FlownRoute, val line: List<site.wingspot.core.GeoCoordinate>)

/** One check-in on its own page: who, when and what, the photos, salute, and the comments with a field to write a new one. */
@Composable
fun CheckInPage(app: WingspotApp, model: SocialViewModel, checkIn: CheckInViewModel, id: String, me: String, reference: ReferenceState = ReferenceState()) {
    val scope = rememberCoroutineScope()
    val feed by model.state.collectAsState()
    var loaded by remember { mutableStateOf<FeedItem?>(null) }
    var gone by remember { mutableStateOf(false) }
    var photos by remember { mutableStateOf(emptyList<FeedPhoto>()) }
    var comments by remember { mutableStateOf(emptyList<CheckInComment>()) }
    var commentsFailed by remember { mutableStateOf(false) }
    var extras by remember { mutableStateOf(emptyMap<String, SocialApi.CommentExtra>()) }
    // Friends who can be mentioned, loaded the first time an "@" is typed.
    var friends by remember { mutableStateOf(emptyList<site.wingspot.core.Person>()) }
    var friendsLoaded by remember { mutableStateOf(false) }
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
    // Friends who added this check-in to their own logbook. Only filled for your own check-ins.
    var copies by remember { mutableStateOf(emptyList<site.wingspot.core.Person>()) }
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
            if (fromList?.userId == me || loaded?.userId == me) copies = runCatching { app.social.checkInCopies(id) }.getOrDefault(emptyList())
            comments = app.social.comments(id)
            model.setCommentCount(id, comments.size)
            extras = runCatching { app.social.commentExtras(id) }.getOrDefault(extras)
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
                            val from = shown.originId
                            val to = shown.destinationId
                            if (shown.kind == "flown" && from != null && to != null) {
                                DropdownMenuItem(text = { Text(stringResource(R.string.return_flight)) }, onClick = {
                                    menu = false
                                    scope.launch {
                                        val db = reference.database
                                        val origin = db?.airport(from)
                                        val destination = db?.airport(to)
                                        if (origin == null || destination == null) { problem = R.string.error_unknown; return@launch }
                                        val day = runCatching { OffsetDateTime.parse(shown.occurredAt).toLocalDate() }.getOrNull()?.let { minOf(it, java.time.LocalDate.now()) } ?: java.time.LocalDate.now()
                                        checkIn.startReturn(ReturnStart(destination, origin, day, shown.cabin?.let { CabinClass.fromWire(it) }, tags.filter { it.id != me }))
                                    }
                                })
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
                        // The route from an imported KML file stays on this phone, so only your own flights have one.
                        val flown by produceState<FlownTrack?>(null, shown.id, shown.distanceKm, me) {
                            value = if (shown.userId == me) withContext(Dispatchers.Default) {
                                app.tracks.load(UUID.fromString(shown.id))?.let { points ->
                                    site.wingspot.core.FlightTrack.flownRoute(points, shown.distanceKm)?.let {
                                        FlownTrack(it, site.wingspot.core.FlightTrack.simplified(points, 300.0))
                                    }
                                }
                            } else null
                        }
                        flown?.let { f ->
                            val r = f.route
                            InfoRow(stringResource(R.string.flown_distance_label), unit.format(r.flownKm))
                            if (r.extraKm > 0) InfoRow(stringResource(R.string.detour_label), "+" + unit.format(r.extraKm) + " (+" + r.percent + " %)")
                            TrackMap(f.line, Modifier.fillMaxWidth().height(220.dp).clip(MaterialTheme.shapes.medium))
                            Text(stringResource(R.string.route_note), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            items(photos, key = { it.id }) { photo ->
                Box {
                    RemoteImage(photo, Modifier.fillMaxWidth().clip(MaterialTheme.shapes.medium).clickable { viewing = photo })
                    if (shown.userId != me) TextButton(onClick = { reporting = ReportKind.PHOTO to photo.id }, modifier = Modifier.align(Alignment.TopEnd)) { Text(stringResource(R.string.report)) }
                }
            }
            feed.badges[id]?.takeIf { it.isNotEmpty() }?.let { earned ->
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(stringResource(R.string.badges_earned_title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                        FeedBadgesLine(earned)
                    }
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
            if (shown.kind == "airport" || shown.kind == "spotted") item { CheckInSpotSection(app, model, id, shown.kind) }
            if (copies.isNotEmpty()) item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.copies_label), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column {
                            copies.forEachIndexed { index, person ->
                                if (index > 0) HorizontalDivider(Modifier.padding(start = 64.dp))
                                Row(
                                    Modifier.fillMaxWidth().clickable { model.openPerson(person.id) }.padding(horizontal = 12.dp, vertical = 10.dp),
                                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                                ) {
                                    Avatar(person.id, person.who, 40.dp)
                                    Text(person.who, style = MaterialTheme.typography.bodyLarge)
                                }
                            }
                        }
                    }
                    Text(stringResource(R.string.copies_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    SaluteButton(shown) { model.toggleSalute(id) }
                    // Your own flights, visits and sightings can be shared as a picture.
                    if (shown.userId == me) {
                        val context = androidx.compose.ui.platform.LocalContext.current
                        val card = shareCardOf(shown, stringResource(R.string.share_flown), stringResource(R.string.share_airport), stringResource(R.string.share_spotted))
                        if (card != null) OutlinedButton(onClick = { scope.launch { ShareCards.share(app, context, me, card) } }, modifier = Modifier.testTag("share-card")) { Text(stringResource(R.string.invite_share)) }
                    }
                }
            }
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
                            val extra = extras[comment.id]
                            Text(mentionText(comment.body, extra?.mentions.orEmpty()) { model.openPerson(it) }, style = MaterialTheme.typography.bodyLarge)
                            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                                if (comment.userId != me) TextButton(onClick = {
                                    text = CommentText.replying(comment.profiles?.username ?: "", text)
                                }, modifier = Modifier.testTag("reply")) { Text(stringResource(R.string.reply)) }
                                val saluteLabel = stringResource(if (extra?.saluted == true) R.string.salute_comment_on else R.string.salute_comment) + (extra?.salutes?.takeIf { it > 0 }?.let { " $it" } ?: "")
                                TextButton(onClick = {
                                    val before = extra ?: SocialApi.CommentExtra(comment.id)
                                    val now = !before.saluted
                                    extras = extras + (comment.id to before.copy(saluted = now, salutes = (before.salutes + if (now) 1 else -1).coerceAtLeast(0)))
                                    scope.launch {
                                        try { app.social.setCommentSalute(comment.id, now) } catch (e: ApiException) { extras = extras + (comment.id to before) }
                                    }
                                }, modifier = Modifier.testTag("salute-comment").semantics {
                                    contentDescription = saluteLabel
                                }) {
                                    // The hand with the count, as on iOS; filled once you saluted.
                                    Icon(
                                        painterResource(if (extra?.saluted == true) R.drawable.ic_glyph_salute_filled else R.drawable.ic_glyph_salute),
                                        contentDescription = null, modifier = Modifier.size(18.dp),
                                    )
                                    extra?.salutes?.takeIf { it > 0 }?.let { Text(it.toString(), Modifier.padding(start = 6.dp)) }
                                }
                            }
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
                    val prefix = CommentText.activePrefix(text)
                    LaunchedEffect(prefix != null) {
                        if (prefix != null && !friendsLoaded) { friendsLoaded = true; friends = runCatching { app.social.taggableFriends() }.getOrDefault(emptyList()) }
                    }
                    val suggestions = if (prefix == null) emptyList() else friends.filter { it.id != me }
                        .filter { prefix.isEmpty() || it.username.startsWith(prefix) || it.who.lowercase().contains(prefix) }.take(10)
                    if (suggestions.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()).testTag("mention-suggestions"), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        for (person in suggestions) {
                            Row(
                                Modifier.background(MaterialTheme.colorScheme.surfaceVariant, CircleShape).clickable { text = CommentText.completing(text, person.username) }
                                    .padding(start = 6.dp, end = 12.dp, top = 4.dp, bottom = 4.dp),
                                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                Avatar(person.id, person.who, 24.dp)
                                Text(person.who, style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
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
                                        extras = runCatching { app.social.commentExtras(id) }.getOrDefault(extras)
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

    if (confirmDelete) DeleteCheckInDialog(
        onConfirm = {
            confirmDelete = false
            scope.launch {
                if (app.outbox.delete(UUID.fromString(id))) { model.remove(id); checkIn.reload(); model.back() } else problem = R.string.delete_failed
            }
        },
        onDismiss = { confirmDelete = false },
    )
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

/** What a check-in earned, as a line on its card: the badge's symbol, name and, for a leveled one, its level. */
@Composable
fun FeedBadgesLine(badges: List<site.wingspot.core.SocialApi.FeedBadge>) {
    val langs = languages()
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        for (badge in badges) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                BadgeSymbol(badge.category, badge.level, badge.levels.size, 24)
                Text(badge.title(langs), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                if (!badge.isSingle) Text(stringResource(R.string.level_n, badge.level), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}


/** A comment's text with each mentioned @name in the accent colour, bold, as a link to that person's page. */
@Composable
private fun mentionText(body: String, mentions: List<SocialApi.CommentMention>, onPerson: (String) -> Unit): androidx.compose.ui.text.AnnotatedString {
    if (mentions.isEmpty()) return androidx.compose.ui.text.AnnotatedString(body)
    val byName = mentions.associate { it.username to it.id }
    val color = MaterialTheme.colorScheme.primary
    return androidx.compose.ui.text.buildAnnotatedString {
        var at = 0
        for ((range, name) in CommentText.mentionRanges(body, byName.keys)) {
            if (range.first < at) continue
            append(body.substring(at, range.first))
            val person = byName.getValue(name)
            withLink(androidx.compose.ui.text.LinkAnnotation.Clickable(person) { onPerson(person) }) {
                withStyle(androidx.compose.ui.text.SpanStyle(color = color, fontWeight = FontWeight.SemiBold)) { append(body.substring(range.first, range.last + 1)) }
            }
            at = range.last + 1
        }
        append(body.substring(at))
    }
}


/** The share card of one of your own check-ins. */
private fun shareCardOf(item: site.wingspot.core.FeedItem, flown: String, airport: String, spotted: String): ShareCardModel? {
    val date = runCatching { java.text.DateFormat.getDateInstance(java.text.DateFormat.MEDIUM).format(java.util.Date(OffsetDateTime.parse(item.occurredAt).toInstant().toEpochMilli())) }.getOrDefault("")
    return when (item.kind) {
        "flown" -> {
            val from = item.originCode ?: return null
            val to = item.destinationCode ?: return null
            ShareCardModel(flown, "$from → $to", item.distanceKm?.let { java.text.NumberFormat.getIntegerInstance().format(it) + " km" },
                listOfNotNull(item.flightNumber, item.typeName, date).joinToString(" · "), "$from → $to (Wingspot)")
        }
        "airport" -> item.airportCode?.let { ShareCardModel(airport, it, null, date, "$it (Wingspot)") }
        else -> (item.registration ?: item.typeIcao)?.let { ShareCardModel(spotted, it, item.typeName, date, "$it (Wingspot)") }
    }
}
