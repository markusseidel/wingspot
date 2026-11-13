package site.wingspot.app

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import kotlinx.coroutines.delay
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import site.wingspot.core.BoardingPass
import site.wingspot.core.ApiException
import site.wingspot.core.Registration
import site.wingspot.core.Username

@Composable
fun AppScreen(app: WingspotApp, model: AppViewModel, reference: ReferenceViewModel, checkIn: CheckInViewModel, social: SocialViewModel) {
    val state by model.state.collectAsState()
    val refState by reference.state.collectAsState()
    val checkInState by checkIn.state.collectAsState()
    val session = state.session
    val me = session?.user?.id
    val editing = checkInState.editing
    val formOpen = checkInState.isOpen || editing != null
    val page = social.stack.lastOrNull()

    BackHandler(enabled = page != null) { social.back() }
    BackHandler(enabled = page == null && formOpen) { if (editing != null) checkIn.cancelEdit() else checkIn.close() }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        bottomBar = {
            if (!formOpen && page == null) NavigationBar {
                for ((tab, label, glyph) in listOf(
                    Triple(Tab.FEED, R.string.tab_feed, "📰"), Triple(Tab.CHECK_IN, R.string.tab_check_in, "✈️"),
                    Triple(Tab.PEOPLE, R.string.tab_people, "👥"), Triple(Tab.ACCOUNT, R.string.tab_account, "👤"),
                )) NavigationBarItem(
                    selected = social.tab == tab, onClick = { social.tab = tab },
                    icon = { Text(glyph) }, label = { Text(stringResource(label)) }, modifier = Modifier.testTag("tab-$tab"),
                )
            }
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).safeDrawingPadding().padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            when {
                editing != null -> Scrolling { FlownEditScreen(editing, checkInState, refState, checkIn) }
                checkInState.isOpen -> Scrolling { CheckInScreen(checkInState, refState, checkIn) }
                page is Route.CheckInPage && me != null -> CheckInPage(app, social, checkIn, page.id, me)
                page is Route.PersonPage && me != null -> PersonPage(app, social, page.id, me)
                else -> when (social.tab) {
                    Tab.FEED -> SocialGate(app, me, onSignIn = { social.tab = Tab.ACCOUNT }) { FeedTab(social, it) }
                    Tab.PEOPLE -> SocialGate(app, me, onSignIn = { social.tab = Tab.ACCOUNT }) { PeopleTab(app, social, it) }
                    Tab.CHECK_IN -> Scrolling {
                        Spacer(Modifier.height(16.dp))
                        Button(onClick = checkIn::open, modifier = Modifier.fillMaxWidth().testTag("open-check-in")) { Text(stringResource(R.string.check_in)) }
                        if (checkInState.deleteFailed) {
                            Text(stringResource(R.string.delete_failed), color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("delete-failed"))
                        }
                        RecentCheckIns(checkInState.recent, onEdit = checkIn::edit, onDelete = checkIn::delete)
                    }
                    Tab.ACCOUNT -> Scrolling {
                        Spacer(Modifier.height(16.dp))
                        when {
                            session != null -> SignedIn(session.user.email ?: session.user.id, onSignOut = { social.clear(); model.signOut() })
                            state.sentTo != null -> CheckEmail(state.sentTo!!, model::useOtherEmail)
                            else -> SignInForm(state.isWorking, model::sendLink)
                        }
                        if (me != null) {
                            HorizontalDivider()
                            SocialSettings(app, me)
                        }
                        HorizontalDivider()
                        SearchSection(refState, reference::search, reference::refresh)
                        state.error?.let { Text(stringResource(it), color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("error")) }
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
private fun SocialGate(app: WingspotApp, me: String?, onSignIn: () -> Unit, content: @Composable (String) -> Unit) {
    if (me == null) {
        Scrolling {
            Spacer(Modifier.height(24.dp))
            Text(stringResource(R.string.sign_in_for_social), style = MaterialTheme.typography.titleMedium)
            Button(onClick = onSignIn) { Text(stringResource(R.string.sign_in_title)) }
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
private fun SignInForm(isWorking: Boolean, onSend: (String) -> Unit) {
    var email by rememberSaveable { mutableStateOf("") }
    Text(stringResource(R.string.sign_in_title), style = MaterialTheme.typography.headlineMedium)
    OutlinedTextField(
        value = email, onValueChange = { email = it }, singleLine = true,
        label = { Text(stringResource(R.string.email_label)) },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
        modifier = Modifier.fillMaxWidth().testTag("email"),
    )
    Text(stringResource(R.string.sign_in_hint), style = MaterialTheme.typography.bodySmall)
    Button(onClick = { onSend(email) }, enabled = !isWorking && email.isNotBlank(), modifier = Modifier.fillMaxWidth().testTag("send")) {
        if (isWorking) CircularProgressIndicator(Modifier.height(20.dp)) else Text(stringResource(R.string.send_link))
    }
}

@Composable
private fun CheckEmail(address: String, onOther: () -> Unit) {
    Text(stringResource(R.string.check_email_title), style = MaterialTheme.typography.headlineMedium)
    Text(stringResource(R.string.check_email_body, address))
    TextButton(onClick = onOther) { Text(stringResource(R.string.use_other_email)) }
}

@Composable
private fun SignedIn(who: String, onSignOut: () -> Unit) {
    Text(stringResource(R.string.signed_in_as, who), style = MaterialTheme.typography.titleMedium)
    OutlinedButton(onClick = onSignOut) { Text(stringResource(R.string.sign_out)) }
    HorizontalDivider()
    RegistrationCheck()
    HorizontalDivider()
    PassReader()
}

/** Shows the shared registration rules at work: type D-AIMA or hbjna. */
@Composable
private fun RegistrationCheck() {
    var text by rememberSaveable { mutableStateOf("") }
    Text(stringResource(R.string.registration_title), style = MaterialTheme.typography.titleMedium)
    OutlinedTextField(
        value = text, onValueChange = { text = it }, singleLine = true,
        label = { Text(stringResource(R.string.registration_label)) }, modifier = Modifier.fillMaxWidth(),
    )
    if (text.isNotBlank()) {
        val registration = Registration.parse(text)
        if (registration != null) {
            Text(
                stringResource(R.string.registration_valid, registration.value, registration.countryCode),
                fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.titleLarge,
            )
        } else {
            Text(stringResource(R.string.registration_invalid))
        }
    }
}

/** Reads pasted barcode text with the shared parser. The camera scan comes later (ML Kit). */
@Composable
private fun PassReader() {
    var barcode by rememberSaveable { mutableStateOf("") }
    var result by remember { mutableStateOf<Result<BoardingPass>?>(null) }
    Text(stringResource(R.string.scan_title), style = MaterialTheme.typography.titleMedium)
    Text(stringResource(R.string.scan_hint), style = MaterialTheme.typography.bodySmall)
    OutlinedTextField(
        value = barcode, onValueChange = { barcode = it },
        label = { Text(stringResource(R.string.barcode_label)) }, modifier = Modifier.fillMaxWidth(),
    )
    Button(onClick = { result = runCatching { BoardingPass.parse(barcode) } }, enabled = barcode.isNotBlank()) {
        Text(stringResource(R.string.read_pass))
    }
    result?.fold(
        onSuccess = { pass ->
            pass.legs.forEach { leg ->
                Text(stringResource(R.string.leg_line, leg.from, leg.to, leg.carrier, leg.flightNumber, leg.flightDate(java.time.LocalDate.now()).toString()))
                leg.seat?.let { Text(stringResource(R.string.seat_line, it)) }
            }
        },
        onFailure = { Text(stringResource(R.string.scan_failed), color = MaterialTheme.colorScheme.error) },
    )
}

/** Airports and aircraft types, searched on the phone. The data is downloaded once and then works offline. */
@Composable
private fun SearchSection(state: ReferenceState, onSearch: (String) -> Unit, onRetry: () -> Unit) {
    var text by rememberSaveable { mutableStateOf("") }
    LaunchedEffect(text, state.database) {
        delay(250)
        onSearch(text)
    }
    Text(stringResource(R.string.search_title), style = MaterialTheme.typography.titleMedium)
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
                label = { Text(stringResource(R.string.search_label)) }, modifier = Modifier.fillMaxWidth().testTag("search"),
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
