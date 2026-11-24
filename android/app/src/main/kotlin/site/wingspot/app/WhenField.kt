package site.wingspot.app

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import site.wingspot.core.WhenChoice

/**
 * The "When" part of a sighting or an airport check-in (#312): "Now" by default, or a day in the past, with a time when the person
 * knows it. A photo's capture date is offered as a tap-to-use suggestion; it never changes the field by itself.
 * During a session at a backdated visit, [visit] is the choice of the visit, which the sighting starts with.
 */
@Composable
internal fun WhenField(choice: WhenChoice, onChange: (WhenChoice) -> Unit, photos: List<PreparedPhoto> = emptyList(), visit: WhenChoice? = null) {
    var pickDate by remember { mutableStateOf(false) }
    var pickTime by remember { mutableStateOf(false) }
    val zone = ZoneId.systemDefault()
    val suggestion = if (choice.isNow) WhenChoice.suggestion(photos.mapNotNull { it.takenAt }.minOrNull()) else null
    Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.testTag("when-field")) {
        if (choice.isNow) {
            Row(
                Modifier.fillMaxWidth().clickable { onChange(WhenChoice(false, LocalDate.now(), null)) }.padding(vertical = 8.dp).testTag("when-now"),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(stringResource(R.string.when_label), Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                Text(stringResource(R.string.when_now) + "  ›", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            Text(stringResource(R.string.when_label), style = MaterialTheme.typography.labelLarge)
            if (visit != null && visit == choice) {
                Text(stringResource(R.string.when_same_as_visit), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { pickDate = true }, modifier = Modifier.testTag("when-date")) {
                    Text(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(choice.day ?: LocalDate.now()))
                }
                TextButton(onClick = { onChange(WhenChoice.NOW) }, modifier = Modifier.testTag("when-back-to-now")) { Text(stringResource(R.string.when_now)) }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.when_set_time), Modifier.weight(1f))
                Switch(
                    checked = choice.time != null,
                    onCheckedChange = { on -> onChange(choice.copy(time = if (on) LocalTime.now().withSecond(0).withNano(0) else null)) },
                    modifier = Modifier.testTag("when-time-switch"),
                )
            }
            choice.time?.let { time ->
                OutlinedButton(onClick = { pickTime = true }, modifier = Modifier.testTag("when-time")) {
                    Text(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).format(time))
                }
            }
            Text(stringResource(R.string.when_help), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (suggestion != null) {
            val text = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).format(suggestion.atZone(zone))
            Column(Modifier.fillMaxWidth().clickable { onChange(WhenChoice.usingPhoto(suggestion, zone)) }.padding(vertical = 8.dp).testTag("when-photo")) {
                Text(stringResource(R.string.when_photo_taken, text))
                Text(stringResource(R.string.when_use_date), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
            }
        }
    }
    if (pickDate) {
        FlightDatePicker(choice.day ?: LocalDate.now(), onPick = { onChange(choice.copy(isNow = false, day = it)); pickDate = false }, onDismiss = { pickDate = false })
    }
    if (pickTime) {
        TimeDialog(choice.time ?: LocalTime.now(), onPick = { onChange(choice.copy(isNow = false, time = it)); pickTime = false }, onDismiss = { pickTime = false })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TimeDialog(time: LocalTime, onPick: (LocalTime) -> Unit, onDismiss: () -> Unit) {
    val state = rememberTimePickerState(initialHour = time.hour, initialMinute = time.minute, is24Hour = android.text.format.DateFormat.is24HourFormat(androidx.compose.ui.platform.LocalContext.current))
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = { TextButton(onClick = { onPick(LocalTime.of(state.hour, state.minute)) }) { Text(stringResource(R.string.done)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
        text = { TimePicker(state = state) },
    )
}

/** A moment shown as a date, with the time only when it is known. */
internal fun momentText(at: Instant, timeKnown: Boolean): String {
    val zoned = at.atZone(ZoneId.systemDefault())
    return if (timeKnown) DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).format(zoned)
    else DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(zoned)
}
