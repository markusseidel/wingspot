package site.wingspot.app

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
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
import site.wingspot.core.SharingChoice

private fun SharingChoice.label(): Int = when (this) {
    SharingChoice.ONLY_ME -> R.string.share_only_me
    SharingChoice.FRIENDS -> R.string.share_friends
    SharingChoice.FOLLOWERS -> R.string.share_followers
    SharingChoice.EVERYONE -> R.string.share_everyone
}

/** What one check-in is set to: its own level, or the account's choice. Null while loading or when it isn't on the server yet. */
private class CheckInVisibility(val level: SharingChoice, val custom: Boolean)

@Composable
private fun rememberVisibility(app: WingspotApp, id: String, reload: Int): Pair<CheckInVisibility?, Boolean> {
    var value by remember(id, reload) { mutableStateOf<CheckInVisibility?>(null) }
    var failed by remember(id, reload) { mutableStateOf(false) }
    LaunchedEffect(id, reload) {
        try { app.social.checkInVisibility(id)?.let { value = CheckInVisibility(it.first, it.second) } } catch (e: ApiException) { failed = true }
    }
    return value to failed
}

/** The "Who can see this" row of a check-in you own, with what it is set to. Hidden until the check-in is on the server. */
@Composable
fun VisibilityRow(app: WingspotApp, id: String) {
    var reload by remember { mutableStateOf(0) }
    var open by remember { mutableStateOf(false) }
    val (current, _) = rememberVisibility(app, id, reload)
    if (current == null) return
    Row(Modifier.fillMaxWidth().clickable { open = true }.testTag("visibility-row"), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        Text(stringResource(R.string.who_can_see))
        Text(stringResource(current.level.label()) + " ›", color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(vertical = 12.dp))
    }
    if (open) VisibilityDialog(app, id, onClose = { open = false; reload++ })
}

/** Choose who can see one check-in: your own choice for it, or "same as my sharing setting". Saved at once. */
@Composable
fun VisibilityDialog(app: WingspotApp, id: String, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    val (current, failedToLoad) = rememberVisibility(app, id, 0)
    var failed by remember { mutableStateOf(false) }
    fun choose(choice: SharingChoice?) {
        scope.launch {
            try { app.social.setCheckInVisibility(id, choice); onClose() } catch (e: ApiException) { failed = true }
        }
    }
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text(stringResource(R.string.who_can_see)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                when {
                    current != null -> {
                        Row(Modifier.fillMaxWidth().clickable { choose(null) }, verticalAlignment = Alignment.CenterVertically) {
                            RadioButton(selected = !current.custom, onClick = { choose(null) }, modifier = Modifier.testTag("visibility-default"))
                            Text(stringResource(R.string.same_as_settings))
                        }
                        for (option in SharingChoice.entries) {
                            Row(Modifier.fillMaxWidth().clickable { choose(option) }, verticalAlignment = Alignment.CenterVertically) {
                                RadioButton(selected = current.custom && current.level == option, onClick = { choose(option) }, modifier = Modifier.testTag("visibility-$option"))
                                Text(stringResource(option.label()))
                            }
                        }
                        if (!current.custom) Text(stringResource(R.string.now_shown_to, stringResource(current.level.label())), style = MaterialTheme.typography.bodySmall)
                    }
                    failedToLoad -> Text(stringResource(R.string.error_unknown), color = MaterialTheme.colorScheme.error)
                    else -> CircularProgressIndicator()
                }
                if (failed) Text(stringResource(R.string.error_unknown), color = MaterialTheme.colorScheme.error)
            }
        },
        confirmButton = { TextButton(onClick = onClose) { Text(stringResource(R.string.close)) } },
    )
}
