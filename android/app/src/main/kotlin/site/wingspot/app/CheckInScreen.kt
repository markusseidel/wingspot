package site.wingspot.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlinx.coroutines.delay
import site.wingspot.core.AircraftType
import site.wingspot.core.Airport
import site.wingspot.core.History
import site.wingspot.core.LocalCheckIn
import site.wingspot.core.Registration
import site.wingspot.core.SpottedResult
import site.wingspot.core.SyncState

/** The Spotted check-in: a registration, or a type if it couldn't be read, and where. Saved on the phone first. */
@Composable
fun CheckInScreen(state: CheckInState, reference: ReferenceState, model: CheckInViewModel) {
    val result = state.result
    if (result != null) {
        ResultView(result, onAnother = model::another, onDone = model::close)
        return
    }
    var input by rememberSaveable { mutableStateOf("") }
    var type by remember { mutableStateOf<AircraftType?>(null) }
    var airport by remember { mutableStateOf<Airport?>(null) }
    val registration = Registration.parse(input)
    val canSave = if (input.isNotBlank()) registration != null else type != null

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.spotted_title), style = MaterialTheme.typography.headlineMedium)
        OutlinedTextField(
            value = input, onValueChange = { input = it }, singleLine = true,
            label = { Text(stringResource(R.string.registration_label)) }, modifier = Modifier.fillMaxWidth().testTag("registration"),
        )
        when {
            registration != null -> Text(
                stringResource(R.string.registration_valid, registration.value, registration.countryCode),
                fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.titleLarge,
            )
            input.isNotBlank() -> Text(stringResource(R.string.registration_invalid))
            else -> Text(stringResource(R.string.registration_or_type), style = MaterialTheme.typography.bodySmall)
        }
        if (registration == null) {
            Picker(
                label = stringResource(R.string.type_label), chosen = type?.let { "${it.icaoCode}  ${it.name}" },
                onClear = { type = null },
                search = { text -> reference.database?.searchTypes(text, 5).orEmpty() },
                rowTitle = { it.icaoCode }, rowDetail = { it.name }, onPick = { type = it },
            )
        }
        Picker(
            label = stringResource(R.string.airport_label), chosen = airport?.let { "${it.code}  ${it.name}" },
            onClear = { airport = null },
            search = { text -> reference.database?.searchAirports(text, 5).orEmpty() },
            rowTitle = { it.code }, rowDetail = { it.name }, onPick = { airport = it },
        )
        if (state.saveFailed) Text(stringResource(R.string.error_unknown), color = MaterialTheme.colorScheme.error)
        Button(
            onClick = { model.save(registration, type, airport) }, enabled = canSave,
            modifier = Modifier.fillMaxWidth().testTag("save"),
        ) { Text(stringResource(R.string.save)) }
        TextButton(onClick = model::close) { Text(stringResource(R.string.cancel)) }
    }
}

/** A search box that offers a few matches; picking one fills it in. */
@Composable
private fun <T> Picker(
    label: String, chosen: String?, onClear: () -> Unit, search: suspend (String) -> List<T>,
    rowTitle: (T) -> String, rowDetail: (T) -> String, onPick: (T) -> Unit,
) {
    if (chosen != null) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(chosen, modifier = Modifier.weight(1f))
            TextButton(onClick = onClear) { Text(stringResource(R.string.clear)) }
        }
        return
    }
    var text by rememberSaveable { mutableStateOf("") }
    var matches by remember { mutableStateOf(emptyList<T>()) }
    LaunchedEffect(text) {
        delay(250)
        matches = if (text.isBlank()) emptyList() else search(text)
    }
    OutlinedTextField(
        value = text, onValueChange = { text = it }, singleLine = true,
        label = { Text(label) }, modifier = Modifier.fillMaxWidth(),
    )
    matches.forEach { match ->
        TextButton(onClick = { onPick(match); text = "" }, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.fillMaxWidth()) {
                Text(rowTitle(match), style = MaterialTheme.typography.titleSmall)
                Text(rowDetail(match), style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun ResultView(result: SpottedResult, onAnother: () -> Unit, onDone: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(result.subject, style = MaterialTheme.typography.displaySmall, fontFamily = FontFamily.Monospace)
        when (val history = result.history) {
            History.FirstTime -> Text(stringResource(R.string.first_time), style = MaterialTheme.typography.titleLarge)
            is History.SeenBefore -> {
                Text(stringResource(R.string.seen_again, history.count), style = MaterialTheme.typography.titleLarge)
                val date = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(history.lastSeen.atZone(ZoneId.systemDefault()))
                Text(stringResource(R.string.last_time, date))
            }
        }
        Button(onClick = onAnother, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.check_in_another)) }
        OutlinedButton(onClick = onDone, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.done)) }
    }
}

/** The last check-ins on this phone, with whether the server has them yet. */
@Composable
fun RecentCheckIns(items: List<LocalCheckIn>) {
    if (items.isEmpty()) return
    HorizontalDivider()
    Text(stringResource(R.string.recent_title), style = MaterialTheme.typography.titleMedium)
    items.forEach { c ->
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(c.registration ?: c.typeIcao ?: "?", fontFamily = FontFamily.Monospace)
            Text(
                stringResource(
                    when (c.syncState) {
                        SyncState.PENDING -> R.string.state_pending
                        SyncState.SYNCED -> R.string.state_synced
                        SyncState.REJECTED -> R.string.state_rejected
                    },
                ),
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}
