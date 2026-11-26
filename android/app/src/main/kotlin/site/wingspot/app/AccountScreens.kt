package site.wingspot.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.clickable
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
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

/** Signing out and deleting the account, for the "younger than 16" path; the same steps as in the profile. */
class AccountLeave(val signOut: suspend () -> Unit, val delete: suspend () -> Unit)

/**
 * The community rules, shown once before the social features are used. Accounts are for people 16 and older
 * (docs/MINIMUM-AGE-PLAN.md), so "I agree" waits for "I am 16 or older".
 */
@Composable
fun TermsScreen(app: WingspotApp, me: String, leave: AccountLeave) {
    val scope = rememberCoroutineScope()
    var oldEnough by remember { mutableStateOf(false) }
    var younger by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(top = 24.dp)) {
        Text(stringResource(R.string.rules_title), style = MaterialTheme.typography.titleLarge)
        Text(stringResource(R.string.rules_intro))
        for (rule in listOf(R.string.rule_respect, R.string.rule_share, R.string.rule_spam, R.string.rule_responsible)) Text("✓ " + stringResource(rule))
        Text(stringResource(R.string.rules_report), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(Modifier.fillMaxWidth().clickable { oldEnough = !oldEnough }, verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.age_confirm), modifier = Modifier.weight(1f))
            androidx.compose.material3.Switch(checked = oldEnough, onCheckedChange = { oldEnough = it }, modifier = Modifier.testTag("age-confirm"))
        }
        Button(enabled = oldEnough, onClick = { scope.launch { app.terms.accept(me) } }, modifier = Modifier.fillMaxWidth().testTag("accept-rules")) { Text(stringResource(R.string.i_agree)) }
        TextButton(onClick = { younger = true }, modifier = Modifier.fillMaxWidth().testTag("younger")) { Text(stringResource(R.string.age_younger)) }
    }
    if (younger) YoungerDialog(leave) { younger = false }
}

/** For someone younger than 16: accounts are not for them, Wingspot without an account is. Nothing about the answer is stored. */
@Composable
private fun YoungerDialog(leave: AccountLeave, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var confirmDeleteAgain by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    fun run(step: suspend () -> Unit) {
        busy = true
        scope.launch {
            try { step(); onClose() } catch (e: ApiException) { failed = true }
            busy = false
        }
    }
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text(stringResource(R.string.age_younger_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.age_younger_message))
                Text(stringResource(R.string.age_younger_delete_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (failed) Text(stringResource(R.string.error_unknown), color = MaterialTheme.colorScheme.error)
                TextButton(enabled = !busy, onClick = { confirmDelete = true }, modifier = Modifier.testTag("younger-delete")) {
                    Text(stringResource(R.string.age_delete_my_account), color = MaterialTheme.colorScheme.error)
                }
            }
        },
        confirmButton = { TextButton(enabled = !busy, onClick = { run(leave.signOut) }, modifier = Modifier.testTag("younger-sign-out")) { Text(stringResource(R.string.sign_out)) } },
        dismissButton = { TextButton(onClick = onClose) { Text(stringResource(R.string.cancel)) } },
    )
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
            TextButton(modifier = Modifier.testTag("younger-confirm-delete"), onClick = { confirmDeleteAgain = false; run(leave.delete) }) {
                Text(stringResource(R.string.delete_account), color = MaterialTheme.colorScheme.error)
            }
        },
        dismissButton = { TextButton(onClick = { confirmDeleteAgain = false }) { Text(stringResource(R.string.cancel)) } },
    )
}

/** This build is older than the server's minimum (docs/MINIMUM-AGE-PLAN.md 4a). The logbook keeps working; the social parts wait. */
@Composable
fun UpdateScreen() {
    val context = androidx.compose.ui.platform.LocalContext.current
    Column(verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(top = 24.dp)) {
        Text(stringResource(R.string.update_title), style = MaterialTheme.typography.titleLarge)
        Text(stringResource(R.string.update_message))
        Button(
            onClick = {
                // The testers get Wingspot through Firebase App Distribution; its page lists the apps they can install.
                runCatching { context.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(UPDATE_URL))) }
            },
            modifier = Modifier.fillMaxWidth().testTag("update-app"),
        ) { Text(stringResource(R.string.update_button)) }
    }
}

private const val UPDATE_URL = "https://appdistribution.firebase.google.com/testerapps"

/** A new account has a made-up username. This asks for a real one before the person is seen by others. */
@Composable
fun ProfileSetup(app: WingspotApp, me: String, onDone: () -> Unit) {
    val scope = rememberCoroutineScope()
    var username by remember { mutableStateOf("") }
    var displayName by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<Int?>(null) }
    val name = Username.normalized(username)
    Column(verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(top = 24.dp)) {
        Text(stringResource(R.string.setup_title), style = MaterialTheme.typography.titleLarge)
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
    var allowTags by remember { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(me) { allowTags = runCatching { app.social.allowsTags(me) }.getOrNull() }
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
        Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.allow_tags), modifier = Modifier.weight(1f))
            androidx.compose.material3.Switch(
                checked = allowTags ?: true, enabled = allowTags != null, modifier = Modifier.testTag("allow-tags"),
                onCheckedChange = { value ->
                    val before = allowTags
                    allowTags = value
                    scope.launch { try { app.social.setAllowsTags(me, value) } catch (e: ApiException) { allowTags = before; failed = true } }
                },
            )
        }
        Text(stringResource(R.string.allow_tags_hint), style = MaterialTheme.typography.bodySmall)
        if (failed) Text(stringResource(R.string.error_unknown), color = MaterialTheme.colorScheme.error)
        if (blocked.isNotEmpty()) {
            Text(stringResource(R.string.blocked_title), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp))
            blocked.forEach { person ->
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Avatar(person.id, person.who, 36.dp)
                    Text(person.who, modifier = Modifier.weight(1f))
                    TextButton(onClick = { scope.launch { try { app.social.unblock(person.id, me); blocked = blocked.filterNot { it.id == person.id } } catch (e: ApiException) { failed = true } } }) { Text(stringResource(R.string.unblock)) }
                }
            }
        }
    }
}
