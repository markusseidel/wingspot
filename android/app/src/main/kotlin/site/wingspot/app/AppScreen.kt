package site.wingspot.app

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import java.util.UUID
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import site.wingspot.core.ApiException
import site.wingspot.core.BoardingPass
import site.wingspot.core.FeedPhoto
import site.wingspot.core.Registration
import site.wingspot.core.Username

@Composable
fun AppScreen(app: WingspotApp, model: AppViewModel, reference: ReferenceViewModel, checkIn: CheckInViewModel, social: SocialViewModel, badges: BadgesViewModel, announcements: AnnouncementsViewModel) {
    val state by model.state.collectAsState()
    val socialState by social.state.collectAsState()
    val refState by reference.state.collectAsState()
    val checkInState by checkIn.state.collectAsState()
    val session = state.session
    val me = session?.user?.id
    val editing = checkInState.editing
    val formOpen = checkInState.isOpen || editing != null
    val page = social.stack.lastOrNull()
    // Badges follow the signed-in person and are refreshed when check-ins reach the server.
    val synced = checkInState.recent.count { it.syncState == site.wingspot.core.SyncState.SYNCED }
    // On Android 13 and newer notifications need the person's yes. Asked once after signing in, so pushes can arrive
    // without a trip into the settings; Push.register runs when it is given.
    val askForNotifications = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted -> if (granted) Push.register(app) }
    LaunchedEffect(me) {
        badges.begin(me)
        if (me != null) {
            Push.register(app)
            if (Push.isAvailable(app) && !Push.isAllowed(app) && !app.prefs.askedForNotifications) {
                app.prefs.askedForNotifications = true
                askForNotifications.launch(android.Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }
    // The photos of the check-in being edited, so the edit screen can show them.
    LaunchedEffect(checkInState.editing?.id, me) { checkInState.editing?.let { if (me != null) social.ensurePhotos(it.id.toString()) } }
    // Also when it goes down: deleting a check-in can take a badge back.
    LaunchedEffect(synced) { if (me != null) badges.refresh() }
    // After a check-in, a flight or an edit went up, the lists show it without a pull to refresh.
    LaunchedEffect(me) { app.uploads.collect { if (me != null) { checkIn.reload(); social.refresh() } } }
    CelebrationDialog(badges)
    social.pendingInvite?.let { owner ->
        if (me != null) AlertDialog(
            onDismissRequest = social::dismissInvite,
            title = { Text(stringResource(R.string.invite_follow_title, owner.who)) },
            text = { Text(stringResource(R.string.invite_follow_message)) },
            confirmButton = { TextButton(onClick = social::followPendingInvite) { Text(stringResource(R.string.follow)) } },
            dismissButton = { TextButton(onClick = social::dismissInvite) { Text(stringResource(R.string.not_now)) } },
        )
    }

    BackHandler(enabled = page != null) { social.back() }
    BackHandler(enabled = page == null && formOpen) { if (editing != null) checkIn.cancelEdit() else checkIn.close() }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        bottomBar = {
            if (!formOpen && page == null) NavigationBar(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest) {
                // Same order and symbols as the iPhone app: Feed, Explore, Check in, Badges, Profile.
                for ((tab, label, icon) in listOf(
                    Triple(Tab.FEED, R.string.tab_feed, R.drawable.ic_tab_feed), Triple(Tab.EXPLORE, R.string.tab_explore, R.drawable.ic_tab_explore),
                    Triple(Tab.CHECK_IN, R.string.tab_check_in, R.drawable.ic_tab_check_in), Triple(Tab.BADGES, R.string.tab_badges, R.drawable.ic_tab_badges),
                    Triple(Tab.PROFILE, R.string.tab_profile, R.drawable.ic_tab_profile),
                )) NavigationBarItem(
                    selected = social.tab == tab, onClick = { social.tab = tab },
                    icon = { Icon(painterResource(icon), contentDescription = null) }, label = { Text(stringResource(label)) }, colors = tabColors(), modifier = Modifier.testTag("tab-$tab"),
                )
            }
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).safeDrawingPadding().padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            androidx.compose.runtime.CompositionLocalProvider(LocalCheckIns provides checkInState.all) {
                when {
                    editing != null -> Scrolling {
                        // The photos the check-in has on the server can be deleted here.
                        val existing = socialState.photos[editing.id.toString()].orEmpty()
                        val deletePhoto: suspend (FeedPhoto) -> Boolean = { photo ->
                            social.deletePhoto(photo).also { if (it) runCatching { app.checkIns.removePhoto(UUID.fromString(photo.id)) } }
                        }
                        if (editing.kind == "flown") FlownEditScreen(editing, checkInState, refState, checkIn, existing, deletePhoto)
                        else SimpleEditScreen(app, editing, checkInState, refState, checkIn, existing, deletePhoto)
                    }
                    checkInState.isOpen -> Scrolling { CheckInScreen(checkInState, refState, checkIn) }
                    page is Route.CheckInPage && me != null -> CheckInPage(app, social, checkIn, page.id, me, refState)
                    page is Route.PersonPage && me != null -> PersonPage(app, social, page.id, me)
                    page is Route.ComparePage && me != null -> ComparePage(app, social, page.id, page.name, me)
                    page is Route.AirportPage -> Scrolling { AirportPage(app, social, page.id, me, refState, checkInState.all) }
                    page is Route.AddSpot && me != null -> Scrolling { AddSpotPage(app, social) }
                    page is Route.ReviewSpots && me != null -> Scrolling { ReviewSpotsPage(app, social) }
                    page is Route.SpotPage && me != null -> Scrolling { SpotPage(app, social, page.id) }
                    page is Route.TypePage -> Scrolling { TypePage(app, social, page.code, me, checkInState.all) }
                    page is Route.RegistrationPage -> Scrolling { RegistrationPage(app, social, page.registration, me, checkInState.all) }
                    page is Route.ExploreMap -> ExploreMapPage(app, me, checkInState.all, refState, social)
                    page is Route.AirportsMap -> AirportsMapPage(checkInState.all, refState, social)
                    page is Route.Collections -> CollectionsPage(app, checkInState.all, social, refState)
                    page is Route.CollectionDetail -> CollectionDetailPage(app, page.kind, page.key, checkInState.all, social, refState)
                    page is Route.Leaderboard && me != null -> LeaderboardPage(app, social, me)
                    page is Route.Invite && me != null -> InvitePage(app, social, me)
                    page is Route.Inbox && me != null -> InboxPage(social)
                    page is Route.Settings -> SettingsPage(app, me, social)
                    page is Route.ReleaseNotes -> ReleaseNotesPage(app, social)
                    page is Route.EditProfile && me != null -> EditProfilePage(app, me, refState, social)
                    else -> when (social.tab) {
                        Tab.FEED -> SocialGate(app, me, announcements, onSignIn = { social.tab = Tab.PROFILE }) { FeedTab(social, it, announcements, checkIn) }
                        Tab.EXPLORE -> Scrolling { ExploreTab(app, social, me, refState, checkInState.all) }
                        Tab.CHECK_IN -> Scrolling {
                            Spacer(Modifier.height(16.dp))
                            Button(onClick = checkIn::open, modifier = Modifier.fillMaxWidth().testTag("open-check-in")) { Text(stringResource(R.string.check_in)) }
                            if (checkInState.deleteFailed) {
                                Text(stringResource(R.string.delete_failed), color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("delete-failed"))
                            }
                            RecentCheckIns(checkInState.recent, onEdit = checkIn::edit, onDelete = checkIn::delete)
                        }
                        Tab.BADGES -> {
                            val shareContext = androidx.compose.ui.platform.LocalContext.current
                            val shareScope = androidx.compose.runtime.rememberCoroutineScope()
                            BadgesTab(badges, me != null, { social.tab = Tab.PROFILE }) { card -> if (me != null) shareScope.launch { ShareCards.share(app, shareContext, me, card) } }
                        }
                        // ProfileTab scrolls by itself; a second scroll around it crashes ("infinite height").
                        Tab.PROFILE -> ProfileTab(app, state, model, badges, social, refState, reference::search, reference::refresh, checkInState.all, checkIn::reload)
                    }
                }
            }
        }
    }
}

@Composable
private fun Scrolling(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
}

/**
 * The social tabs need a signed-in person with a chosen username who has agreed to the community rules.
 * Shows what is missing instead, and the content once everything is in place.
 */
@Composable
private fun SocialGate(app: WingspotApp, me: String?, announcements: AnnouncementsViewModel, onSignIn: () -> Unit, content: @Composable (String) -> Unit) {
    if (me == null) {
        LaunchedEffect(Unit) { announcements.refresh() }
        Scrolling {
            Text(stringResource(R.string.tab_feed), style = MaterialTheme.typography.headlineMedium, modifier = Modifier.padding(top = 16.dp))
            AnnouncementCards(announcements)
            EmptyState(R.drawable.ic_tab_feed, stringResource(R.string.empty_feed_title), stringResource(R.string.sign_in_for_social)) {
                Button(onClick = onSignIn) { Text(stringResource(R.string.sign_in_title)) }
            }
        }
        return
    }
    var needsName by remember(me) { mutableStateOf<Boolean?>(null) }
    var accepted by remember(me) { mutableStateOf(app.terms.hasAccepted(me)) }
    LaunchedEffect(me) {
        needsName = try { app.social.person(me)?.username?.let(Username::isPlaceholder) ?: false } catch (e: ApiException) { false }
    }
    when {
        needsName == null -> CircularProgressIndicator()
        needsName == true -> Scrolling { ProfileSetup(app, me) { needsName = false } }
        !accepted -> Scrolling { TermsScreen { app.terms.accept(me); accepted = true } }
        else -> content(me)
    }
}

@Composable
internal fun SignInForm(isWorking: Boolean, onSend: (String) -> Unit, onPassword: (String, String) -> Unit, onGoogle: (() -> Unit)?) {
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var withPassword by rememberSaveable { mutableStateOf(false) }
    Text(stringResource(R.string.sign_in_title), style = MaterialTheme.typography.titleLarge)
    if (onGoogle != null) {
        OutlinedButton(onClick = onGoogle, enabled = !isWorking, modifier = Modifier.fillMaxWidth().testTag("google")) { Text(stringResource(R.string.sign_in_google)) }
        Text(stringResource(R.string.or_with_email), style = MaterialTheme.typography.bodySmall)
    }
    OutlinedTextField(
        value = email, onValueChange = { email = it }, singleLine = true,
        label = { Text(stringResource(R.string.email_label)) },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
        modifier = Modifier.fillMaxWidth().testTag("email"),
    )
    if (withPassword) {
        OutlinedTextField(
            value = password, onValueChange = { password = it }, singleLine = true,
            label = { Text(stringResource(R.string.password_label)) },
            visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            modifier = Modifier.fillMaxWidth().testTag("password"),
        )
        Button(onClick = { onPassword(email, password) }, enabled = !isWorking && email.isNotBlank() && password.isNotEmpty(), modifier = Modifier.fillMaxWidth().testTag("sign-in-password")) {
            if (isWorking) CircularProgressIndicator(Modifier.height(20.dp)) else Text(stringResource(R.string.sign_in_title))
        }
        TextButton(onClick = { withPassword = false }) { Text(stringResource(R.string.use_link_instead)) }
    } else {
        Text(stringResource(R.string.sign_in_hint), style = MaterialTheme.typography.bodySmall)
        Button(onClick = { onSend(email) }, enabled = !isWorking && email.isNotBlank(), modifier = Modifier.fillMaxWidth().testTag("send")) {
            if (isWorking) CircularProgressIndicator(Modifier.height(20.dp)) else Text(stringResource(R.string.send_link))
        }
        TextButton(onClick = { withPassword = true }, modifier = Modifier.testTag("use-password")) { Text(stringResource(R.string.use_password_instead)) }
    }
    LegalLinksSection(compact = true)
}

@Composable
internal fun CheckEmail(address: String, onOther: () -> Unit) {
    Text(stringResource(R.string.check_email_title), style = MaterialTheme.typography.titleLarge)
    Text(stringResource(R.string.check_email_body, address))
    TextButton(onClick = onOther) { Text(stringResource(R.string.use_other_email)) }
}

/** Airports and aircraft types, searched on the phone. The data is downloaded once and then works offline. */
@Composable
internal fun SearchSection(state: ReferenceState, onSearch: (String) -> Unit, onRetry: () -> Unit) {
    var text by rememberSaveable { mutableStateOf("") }
    LaunchedEffect(text, state.database) {
        delay(250)
        onSearch(text)
    }
    SectionHeader(stringResource(R.string.search_title))
    when {
        state.database == null && state.isDownloading -> {
            CircularProgressIndicator(Modifier.height(24.dp))
            Text(stringResource(R.string.search_downloading), style = MaterialTheme.typography.bodySmall)
        }
        state.database == null && state.failed -> {
            Text(stringResource(R.string.search_failed), color = MaterialTheme.colorScheme.error)
            OutlinedButton(onClick = onRetry) { Text(stringResource(R.string.try_again)) }
        }
        else -> {
            OutlinedTextField(
                value = text, onValueChange = { text = it }, singleLine = true,
                placeholder = { Text(stringResource(R.string.search_label), maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis) }, modifier = Modifier.fillMaxWidth().testTag("search"),
                leadingIcon = { Icon(painterResource(R.drawable.ic_search), contentDescription = null) },
            )
            if (text.isNotBlank() && state.airports.isEmpty() && state.types.isEmpty()) {
                Text(stringResource(R.string.nothing_found), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (state.airports.isNotEmpty()) Text(stringResource(R.string.airports), style = MaterialTheme.typography.labelLarge)
            state.airports.forEach { airport ->
                Column {
                    Text(airport.code, style = MaterialTheme.typography.titleSmall)
                    Text(listOfNotNull(airport.name, airport.city).joinToString(", "), style = MaterialTheme.typography.bodySmall)
                }
            }
            if (state.types.isNotEmpty()) Text(stringResource(R.string.aircraft_types), style = MaterialTheme.typography.labelLarge)
            state.types.forEach { type ->
                Column {
                    Text(type.icaoCode, style = MaterialTheme.typography.titleSmall)
                    Text(type.name, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}
