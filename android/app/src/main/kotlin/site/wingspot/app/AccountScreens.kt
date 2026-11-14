package site.wingspot.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.clickable
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import site.wingspot.core.ApiException
import site.wingspot.core.Person
import site.wingspot.core.SharingChoice
import site.wingspot.core.Username

/** The community rules, shown once before the social features are used. */
@Composable
fun TermsScreen(onAccept: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(top = 24.dp)) {
        Text(stringResource(R.string.rules_title), style = MaterialTheme.typography.headlineMedium)
        Text(stringResource(R.string.rules_intro))
        for (rule in listOf(R.string.rule_respect, R.string.rule_share, R.string.rule_spam, R.string.rule_responsible)) Text("✓ " + stringResource(rule))
        Text(stringResource(R.string.rules_report), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Button(onClick = onAccept, modifier = Modifier.fillMaxWidth().testTag("accept-rules")) { Text(stringResource(R.string.i_agree)) }
    }
}

/** A new account has a made-up username. This asks for a real one before the person is seen by others. */
@Composable
fun ProfileSetup(app: WingspotApp, me: String, onDone: () -> Unit) {
    val scope = rememberCoroutineScope()
    var username by remember { mutableStateOf("") }
    var displayName by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<Int?>(null) }
    val name = Username.normalized(username)
    Column(verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(top = 24.dp)) {
        Text(stringResource(R.string.setup_title), style = MaterialTheme.typography.headlineMedium)
        Text(stringResource(R.string.setup_hint))
        OutlinedTextField(username, { username = it }, singleLine = true, label = { Text(stringResource(R.string.username_label)) }, modifier = Modifier.fillMaxWidth().testTag("username"))
        if (username.isNotBlank() && !Username.isValid(name)) Text(stringResource(R.string.username_rule), style = MaterialTheme.typography.bodySmall)
        OutlinedTextField(displayName, { displayName = it }, singleLine = true, label = { Text(stringResource(R.string.display_name_label)) }, modifier = Modifier.fillMaxWidth())
        error?.let { Text(stringResource(it), color = MaterialTheme.colorScheme.error) }
        Button(
            enabled = Username.isValid(name), modifier = Modifier.fillMaxWidth().testTag("save-profile"),
            onClick = {
                scope.launch {
                    try { app.social.saveProfile(me, name, displayName); error = null; onDone() }
                    catch (e: ApiException.Failed) { error = if (e.code == "23505") R.string.username_taken else R.string.username_rule }
                    catch (e: ApiException) { error = R.string.error_offline }
                }
            },
        ) { Text(stringResource(R.string.save)) }
    }
}

/** Who may see your check-ins, and the people you blocked. */
@Composable
fun SocialSettings(app: WingspotApp, me: String) {
    val scope = rememberCoroutineScope()
    var choice by remember { mutableStateOf<SharingChoice?>(null) }
    var applyToExisting by remember { mutableStateOf(false) }
    var blocked by remember { mutableStateOf(emptyList<Person>()) }
    var failed by remember { mutableStateOf(false) }
    var changed by remember { mutableStateOf<Int?>(null) }
    LaunchedEffect(me) {
        try { choice = app.social.sharing(me); blocked = app.social.blocked() } catch (e: ApiException) { failed = true }
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.sharing_title), style = MaterialTheme.typography.titleMedium)
        Text(stringResource(R.string.sharing_hint), style = MaterialTheme.typography.bodySmall)
        for ((option, label) in listOf(SharingChoice.ONLY_ME to R.string.share_only_me, SharingChoice.FRIENDS to R.string.share_friends, SharingChoice.FOLLOWERS to R.string.share_followers, SharingChoice.EVERYONE to R.string.share_everyone)) {
            Row(Modifier.fillMaxWidth().clickable { choice = option }, verticalAlignment = Alignment.CenterVertically) {
                RadioButton(selected = choice == option, onClick = { choice = option }, modifier = Modifier.testTag("share-$option"))
                Text(stringResource(label))
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(checked = applyToExisting, onCheckedChange = { applyToExisting = it })
            Text(stringResource(R.string.apply_to_existing))
        }
        Button(enabled = choice != null, onClick = {
            scope.launch { try { changed = app.social.setSharing(choice!!, applyToExisting); failed = false } catch (e: ApiException) { failed = true } }
        }, modifier = Modifier.testTag("save-sharing")) { Text(stringResource(R.string.save)) }
        changed?.let { Text(if (applyToExisting) stringResource(R.string.sharing_saved_n, it) else stringResource(R.string.sharing_saved)) }
        if (failed) Text(stringResource(R.string.error_unknown), color = MaterialTheme.colorScheme.error)
        if (blocked.isNotEmpty()) {
            Text(stringResource(R.string.blocked_title), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp))
            blocked.forEach { person ->
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(person.who, modifier = Modifier.weight(1f))
                    TextButton(onClick = { scope.launch { try { app.social.unblock(person.id, me); blocked = blocked.filterNot { it.id == person.id } } catch (e: ApiException) { failed = true } } }) { Text(stringResource(R.string.unblock)) }
                }
            }
        }
    }
}
