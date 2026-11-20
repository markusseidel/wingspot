package site.wingspot.app

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.text.NumberFormat
import java.util.Locale
import site.wingspot.core.ApiException
import site.wingspot.core.SocialApi

/** You next to a friend: the numbers side by side, and what you share or only one of you has. */
@Composable
fun ComparePage(app: WingspotApp, model: SocialViewModel, id: String, name: String, me: String) {
    var result by remember { mutableStateOf<SocialApi.CompareResult?>(null) }
    var loaded by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(id) {
        try { result = app.social.compare(id); failed = false } catch (e: ApiException) { failed = true }
        loaded = true
    }
    LazyColumn(Modifier.fillMaxWidth().testTag("compare-page"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = model::back) { Text("‹ " + stringResource(R.string.back)) }
                Text(stringResource(R.string.compare_title), style = MaterialTheme.typography.titleLarge)
            }
        }
        val r = result
        when {
            !loaded -> item { CircularProgressIndicator(Modifier.padding(16.dp)) }
            r == null -> item {
                Text(stringResource(if (failed) R.string.compare_failed else R.string.compare_nothing), color = if (failed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
            }
            else -> {
                item {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                        for ((who, label) in listOf(me to stringResource(R.string.you), id to name)) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Avatar(who, label, 56.dp)
                                Text(label, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                }
                item {
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            StatRow(stringResource(R.string.compare_flights), r.me.flights, r.them.flights)
                            StatRow(stringResource(R.string.compare_distance), r.me.distanceKm, r.them.distanceKm, " km")
                            StatRow(stringResource(R.string.compare_countries), r.me.countries, r.them.countries)
                            StatRow(stringResource(R.string.compare_airports), r.me.airports, r.them.airports)
                            StatRow(stringResource(R.string.compare_airlines), r.me.airlines, r.them.airlines)
                            StatRow(stringResource(R.string.compare_types), r.me.types, r.them.types)
                        }
                    }
                }
                item { SetsCard(stringResource(R.string.compare_countries), r.countries, name, country = true) }
                item { SetsCard(stringResource(R.string.compare_airports), r.airports, name) }
                item { SetsCard(stringResource(R.string.compare_airlines), r.airlines, name) }
                item { SetsCard(stringResource(R.string.compare_types), r.types, name) }
                item { Text(stringResource(R.string.compare_footer), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
        }
    }
}

/** A number for each of you, with a bar that shows who has more. */
@Composable
private fun StatRow(title: String, mine: Int, theirs: Int, unit: String = "") {
    val top = maxOf(maxOf(mine, theirs), 1)
    val format = NumberFormat.getIntegerInstance()
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        for ((value, color) in listOf(mine to MaterialTheme.colorScheme.primary, theirs to Color.Gray)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.weight(1f)) {
                    Box(Modifier.fillMaxWidth(if (value == 0) 0f else maxOf(value.toFloat() / top, 0.02f)).height(8.dp).background(color, RoundedCornerShape(4.dp)))
                }
                Text(format.format(value) + unit, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.width(96.dp), textAlign = androidx.compose.ui.text.style.TextAlign.End)
            }
        }
    }
}

/** What is in common, only yours and only theirs, each a list that opens. */
@Composable
private fun SetsCard(title: String, set: SocialApi.CompareSet, theirName: String, country: Boolean = false) {
    if (set.common.isEmpty() && set.mine.isEmpty() && set.theirs.isEmpty()) return
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            OpenList(stringResource(R.string.compare_common), set.common, country, open = country)
            OpenList(stringResource(R.string.compare_only_you), set.mine, country)
            OpenList(stringResource(R.string.compare_only_them, theirName), set.theirs, country)
        }
    }
}

@Composable
private fun OpenList(title: String, items: List<SocialApi.CompareItem>, country: Boolean, open: Boolean = false) {
    if (items.isEmpty()) return
    var expanded by remember { mutableStateOf(open) }
    Column {
        Row(Modifier.fillMaxWidth().clickable { expanded = !expanded }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(title)
            Box(Modifier.weight(1f))
            Text(items.size.toString() + if (expanded) "  \u2303" else "  \u2304", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (expanded) items.forEach { Text(itemLabel(it, country), style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(start = 12.dp, bottom = 4.dp)) }
    }
}

private fun itemLabel(item: SocialApi.CompareItem, country: Boolean): String {
    if (country) {
        val code = item.code.uppercase()
        val flag = code.map { String(Character.toChars(0x1F1E6 + (it - 'A'))) }.joinToString("")
        return flag + " " + Locale("", code).getDisplayCountry(Locale.getDefault()).ifBlank { code }
    }
    return if (!item.name.isNullOrBlank()) item.code + " \u00B7 " + item.name else item.code
}
