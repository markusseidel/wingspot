package site.wingspot.app

import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import site.wingspot.core.AircraftType
import site.wingspot.core.Airport
import site.wingspot.core.KmlBatch
import site.wingspot.core.KmlFlight
import site.wingspot.core.Registration
import site.wingspot.core.departureDay

/**
 * Several KML files at once (#236): one list with a row per file, the ones that can be used ticked, and one button that saves them all as
 * flights, each with its route, which stays on this phone. Nothing is saved before the person confirms.
 */
@Composable
fun KmlBatchScreen(files: List<Uri>, state: CheckInState, reference: ReferenceState, model: CheckInViewModel) {
    val context = LocalContext.current
    class Row(
        val name: String, var status: Status, val flight: KmlFlight?, val origin: Airport?, val destination: Airport?, val type: AircraftType?, val day: LocalDate?,
    )

    val rows = remember { mutableStateListOf<Row>() }
    val selected = remember { mutableStateListOf<Int>() }
    var loading by remember { mutableStateOf(true) }
    var added by remember { mutableStateOf<Int?>(null) }

    LaunchedEffect(files, reference.database) {
        loading = true
        rows.clear(); selected.clear()
        val found = mutableListOf<Row>()
        for (uri in files) {
            val name = uri.lastPathSegment?.substringAfterLast('/')?.substringBeforeLast('.') ?: "KML"
            when (val read = KmlImport.read(context, uri)) {
                is KmlRead.Problem -> found += Row(name, Status.NOT_KML, null, null, null, null, null)
                is KmlRead.Done -> {
                    val db = reference.database
                    val flight = read.flight
                    val from = flight.origin?.iata?.let { db?.airport(it) }
                    val to = flight.destination?.iata?.let { db?.airport(it) }
                    val type = flight.aircraftTypeCode?.let { db?.aircraftType(it) }
                    val day = flight.departureDay()
                    val status = when {
                        db == null -> Status.NO_DATA
                        from == null || to == null || from.id == to.id -> Status.NO_ROUTE
                        day == null -> Status.NO_DATE
                        else -> Status.READY
                    }
                    found += Row(name, status, flight, from, to, type, day)
                }
            }
        }
        // Oldest flight first, the files without a day at the end.
        found.sortBy { it.day ?: LocalDate.MAX }
        val mine = state.all.filter { it.kind == "flown" }.map { KmlBatch.Existing(it.flightNumber, it.occurredAt.atZone(ZoneId.systemDefault()).toLocalDate()) }
        val flags = KmlBatch.duplicates(found.map { KmlBatch.Entry(it.flight?.flightNumber, it.day, it.flight?.flightLink) }, mine)
        found.forEachIndexed { i, row -> if (row.status == Status.READY && flags[i]) row.status = Status.DUPLICATE }
        rows.addAll(found)
        selected.addAll(found.indices.filter { found[it].status == Status.READY })
        loading = false
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.testTag("kml-batch")) {
        Text(stringResource(R.string.kml_files_title), style = MaterialTheme.typography.titleLarge)
        val done = added
        when {
            done != null -> {
                Text(stringResource(R.string.kml_batch_added, done), color = MaterialTheme.colorScheme.primary, modifier = Modifier.testTag("kml-batch-added"))
                Button(onClick = { model.closeKmlFiles(); model.close() }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.done)) }
            }
            loading -> Row(verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.padding(end = 12.dp))
                Text(stringResource(R.string.kml_batch_reading))
            }
            else -> {
                Text(stringResource(R.string.kml_files_count, rows.size), style = MaterialTheme.typography.labelLarge)
                rows.forEachIndexed { index, row ->
                    val usable = row.status == Status.READY || row.status == Status.DUPLICATE
                    Row(
                        Modifier.fillMaxWidth().clickable(enabled = usable) { if (index in selected) selected.remove(index) else selected.add(index) }.padding(vertical = 4.dp).testTag("kml-row-$index"),
                        verticalAlignment = Alignment.Top,
                    ) {
                        Checkbox(checked = index in selected, onCheckedChange = null, enabled = usable)
                        Column(Modifier.padding(start = 8.dp)) {
                            Text(
                                if (row.origin != null && row.destination != null) "${row.origin.code} \u2192 ${row.destination.code}" else row.name,
                                style = MaterialTheme.typography.titleMedium,
                            )
                            val details = listOfNotNull(
                                row.flight?.flightNumber, row.day?.let { java.time.format.DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.MEDIUM).format(it) }, row.flight?.registration,
                            ).joinToString(" \u00b7 ")
                            if (details.isNotEmpty()) Text(details, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            when (row.status) {
                                Status.READY -> {}
                                Status.DUPLICATE -> Text(stringResource(R.string.kml_row_duplicate), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.tertiary)
                                Status.NOT_KML -> Text(stringResource(R.string.kml_row_not_kml), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                                Status.NO_DATA -> Text(stringResource(R.string.kml_row_no_data), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                                Status.NO_ROUTE -> Text(stringResource(R.string.kml_row_no_route), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                                Status.NO_DATE -> Text(stringResource(R.string.kml_row_no_date), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                            }
                        }
                    }
                }
                Text(stringResource(R.string.kml_batch_footer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Button(
                    onClick = {
                        val flights = selected.sorted().mapNotNull { rows.getOrNull(it) }.mapNotNull { r ->
                            val day = r.day ?: return@mapNotNull null
                            val at = if (day == LocalDate.now()) Instant.now() else day.atTime(12, 0).atZone(ZoneId.systemDefault()).toInstant()
                            BatchFlight(r.origin ?: return@mapNotNull null, r.destination ?: return@mapNotNull null, r.flight?.flightNumber, r.flight?.registration?.let { Registration.parse(it) }, r.type, at, r.flight?.track.orEmpty())
                        }
                        model.saveKmlBatch(flights) { added = it }
                    },
                    enabled = selected.isNotEmpty(), modifier = Modifier.fillMaxWidth().testTag("kml-batch-add"),
                ) { Text(stringResource(R.string.kml_batch_add, selected.size)) }
                TextButton(onClick = { model.closeKmlFiles(); model.close() }) { Text(stringResource(R.string.cancel)) }
            }
        }
    }
}

private enum class Status { READY, DUPLICATE, NOT_KML, NO_DATA, NO_ROUTE, NO_DATE }
