package site.wingspot.app

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import site.wingspot.core.ApiException
import site.wingspot.core.SocialApi

/** Asks the phone for permission to show notifications, once, and registers this phone when it is given. */
@Composable
private fun rememberAskForNotifications(app: WingspotApp, onResult: (Boolean) -> Unit): () -> Unit {
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) Push.register(app)
        onResult(granted)
    }
    return {
        if (Push.isAllowed(app)) { Push.register(app); onResult(true) }
        else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
        else onResult(true)
    }
}

/** The kinds of notification you get, and the people you get alerts from. */
@Composable
fun NotificationSettings(app: WingspotApp, me: String) {
    val scope = rememberCoroutineScope()
    var prefs by remember { mutableStateOf<SocialApi.NotificationPrefs?>(null) }
    var rules by remember { mutableStateOf(emptyList<SocialApi.AlertRule>()) }
    var failed by remember { mutableStateOf(false) }
    var denied by remember { mutableStateOf(!Push.isAllowed(app)) }
    val ask = rememberAskForNotifications(app) { denied = !it }
    LaunchedEffect(me) {
        try { prefs = app.social.notificationPrefs(me); rules = app.social.alertRules(me) } catch (e: ApiException) { failed = true }
    }
    fun change(next: SocialApi.NotificationPrefs) {
        val before = prefs ?: return
        prefs = next
        if (next != before) ask()
        scope.launch { try { app.social.setNotificationPrefs(me, next) } catch (e: ApiException) { prefs = before; failed = true } }
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.notifications_title), style = MaterialTheme.typography.titleMedium)
        if (!Push.isAvailable(app)) Text(stringResource(R.string.push_not_in_build), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (denied && Push.isAvailable(app)) {
            Text(stringResource(R.string.notifications_denied), color = MaterialTheme.colorScheme.error)
            OutlinedButton(onClick = {
                app.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, app.packageName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }) { Text(stringResource(R.string.open_phone_settings)) }
        }
        val p = prefs
        for ((label, get, set) in listOf(
            Triple(R.string.notify_followers, { x: SocialApi.NotificationPrefs -> x.newFollowers }, { x: SocialApi.NotificationPrefs, v: Boolean -> x.copy(newFollowers = v) }),
            Triple(R.string.notify_salutes, { x: SocialApi.NotificationPrefs -> x.salutes }, { x: SocialApi.NotificationPrefs, v: Boolean -> x.copy(salutes = v) }),
            Triple(R.string.notify_comments, { x: SocialApi.NotificationPrefs -> x.comments }, { x: SocialApi.NotificationPrefs, v: Boolean -> x.copy(comments = v) }),
            Triple(R.string.notify_followed, { x: SocialApi.NotificationPrefs -> x.followedCheckins }, { x: SocialApi.NotificationPrefs, v: Boolean -> x.copy(followedCheckins = v) }),
        )) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(label), Modifier.weight(1f))
                Switch(checked = p?.let(get) ?: false, enabled = p != null, onCheckedChange = { change(set(p!!, it)) })
            }
        }
        if (rules.isNotEmpty()) {
            Text(stringResource(R.string.alerts_from), style = MaterialTheme.typography.titleSmall)
            rules.forEach { rule ->
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(rule.who)
                        Text(
                            listOfNotNull(
                                if (rule.spotted) stringResource(R.string.alert_spotted) else null,
                                if (rule.flown) stringResource(R.string.alert_flown) else null,
                                if (rule.airport) stringResource(R.string.alert_airport) else null,
                            ).joinToString(" · "),
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    TextButton(onClick = {
                        scope.launch { try { app.social.saveAlertRule(me, rule.copy(spotted = false, flown = false, airport = false)); rules = rules.filterNot { it.target == rule.target } } catch (e: ApiException) { failed = true } }
                    }) { Text(stringResource(R.string.stop)) }
                }
            }
        }
        if (failed) Text(stringResource(R.string.error_unknown), color = MaterialTheme.colorScheme.error)
    }
}

/** "Notify me" on the page of someone you follow: which of their check-ins send you a notification. */
@Composable
fun PersonAlerts(app: WingspotApp, me: String, person: String) {
    val scope = rememberCoroutineScope()
    var rule by remember { mutableStateOf(SocialApi.AlertRule(person)) }
    var loaded by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    var denied by remember { mutableStateOf(false) }
    val ask = rememberAskForNotifications(app) { denied = !it }
    LaunchedEffect(person) {
        try { rule = app.social.alertRules(me).firstOrNull { it.target == person } ?: SocialApi.AlertRule(person); loaded = true } catch (e: ApiException) { failed = true }
    }
    fun change(next: SocialApi.AlertRule) {
        val before = rule
        rule = next
        if (!before.isOn && next.isOn) ask()
        scope.launch { try { app.social.saveAlertRule(me, next); failed = false } catch (e: ApiException) { rule = before; failed = true } }
    }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(stringResource(R.string.notify_me), style = MaterialTheme.typography.titleMedium)
        for ((label, get, set) in listOf(
            Triple(R.string.alert_spotted, { r: SocialApi.AlertRule -> r.spotted }, { r: SocialApi.AlertRule, v: Boolean -> r.copy(spotted = v) }),
            Triple(R.string.alert_flown, { r: SocialApi.AlertRule -> r.flown }, { r: SocialApi.AlertRule, v: Boolean -> r.copy(flown = v) }),
            Triple(R.string.alert_airport, { r: SocialApi.AlertRule -> r.airport }, { r: SocialApi.AlertRule, v: Boolean -> r.copy(airport = v) }),
        )) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(label), Modifier.weight(1f))
                Switch(checked = get(rule), enabled = loaded, onCheckedChange = { change(set(rule, it)) }, modifier = Modifier.testTag("alert-$label"))
            }
        }
        Text(stringResource(R.string.notify_me_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (denied) Text(stringResource(R.string.notifications_denied), color = MaterialTheme.colorScheme.error)
        if (failed) Text(stringResource(R.string.error_unknown), color = MaterialTheme.colorScheme.error)
    }
}
