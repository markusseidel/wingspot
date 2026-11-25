package site.wingspot.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import site.wingspot.core.SocialApi

/** One open request in the inbox: a friend's flight or visit you are tagged on, with the two answers (#273). */
@Composable
fun CompanionRequestRow(request: SocialApi.CompanionRequest, onAccept: () -> Unit, onDecline: () -> Unit) {
    val date = runCatching { DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(OffsetDateTime.parse(request.occurredAt)) }.getOrDefault("")
    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp, horizontal = 4.dp).testTag("companion-request"), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(request.who, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
        Text(listOfNotNull(request.title, request.flightNumber, date.ifEmpty { null }).joinToString(" \u00b7 "), style = MaterialTheme.typography.titleMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = onAccept, modifier = Modifier.testTag("companion-accept")) { Text(stringResource(R.string.add_to_logbook)) }
            OutlinedButton(onClick = onDecline, modifier = Modifier.testTag("companion-decline")) { Text(stringResource(R.string.companion_not_me)) }
        }
    }
}

/** The question "You already logged this flight": keep it, or replace its flight data with the friend's (#273). Also says when it failed. */
@Composable
fun CompanionAskDialog(state: CheckInState, model: CheckInViewModel) {
    val ask = state.companionAsk
    if (ask != null) {
        val match = ask.match
        val number = match.flightNumber ?: listOfNotNull(match.originCode, match.destinationCode).joinToString(" \u2192 ")
        val date = runCatching { DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(OffsetDateTime.parse(match.occurredAt)) }.getOrDefault("")
        AlertDialog(
            onDismissRequest = model::dismissCompanionAsk,
            title = { Text(stringResource(R.string.companion_already_title, number, date)) },
            text = { Text(stringResource(R.string.companion_already_message)) },
            confirmButton = { TextButton(onClick = { model.chooseCompanion(keepMine = false) }, modifier = Modifier.testTag("companion-replace")) { Text(stringResource(R.string.companion_replace)) } },
            dismissButton = {
                Row {
                    TextButton(onClick = { model.chooseCompanion(keepMine = true) }, modifier = Modifier.testTag("companion-keep")) { Text(stringResource(R.string.companion_keep_mine)) }
                    TextButton(onClick = model::dismissCompanionAsk) { Text(stringResource(R.string.cancel)) }
                }
            },
        )
    }
    if (state.companionFailed) {
        AlertDialog(
            onDismissRequest = model::dismissCompanionAsk,
            text = { Text(stringResource(R.string.companion_failed)) },
            confirmButton = { TextButton(onClick = model::dismissCompanionAsk) { Text(stringResource(R.string.done)) } },
        )
    }
}
