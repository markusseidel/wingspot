package site.wingspot.app

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import java.text.NumberFormat
import kotlinx.coroutines.launch
import site.wingspot.core.ApiException
import site.wingspot.core.SocialApi

/** You and the people you follow, ranked. Only people who switched it on are on it. */
@Composable
fun LeaderboardPage(app: WingspotApp, model: SocialViewModel, me: String) {
    val scope = rememberCoroutineScope()
    var metric by remember { mutableStateOf("distance") }
    var period by remember { mutableStateOf("year") }
    var rows by remember { mutableStateOf(emptyList<SocialApi.LeaderboardRow>()) }
    var loaded by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    var shown by remember { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(metric, period) {
        try { rows = app.social.leaderboard(metric, period); failed = false } catch (e: ApiException) { failed = true }
        loaded = true
    }
    LaunchedEffect(me) { shown = runCatching { app.social.showsOnLeaderboard(me) }.getOrNull() }
    val format = NumberFormat.getIntegerInstance()
    LazyColumn(Modifier.fillMaxWidth().testTag("leaderboard"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = model::back) { Text("‹ " + stringResource(R.string.back)) }
                Text(stringResource(R.string.leaderboard_title), style = MaterialTheme.typography.titleLarge)
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for ((key, label) in listOf("distance" to R.string.compare_distance, "flights" to R.string.compare_flights, "countries" to R.string.compare_countries, "airports" to R.string.compare_airports))
                    FilterChip(selected = metric == key, onClick = { metric = key }, label = { Text(stringResource(label)) })
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for ((key, label) in listOf("year" to R.string.leaderboard_year, "all" to R.string.leaderboard_all))
                    FilterChip(selected = period == key, onClick = { period = key }, label = { Text(stringResource(label)) })
            }
        }
        when {
            failed -> item { Text(stringResource(R.string.leaderboard_failed), color = MaterialTheme.colorScheme.error) }
            !loaded -> item { CircularProgressIndicator(Modifier.padding(16.dp)) }
            else -> {
                itemsIndexed(rows, key = { _, row -> row.userId }) { index, row ->
                    val tint = if (row.isMe) MaterialTheme.colorScheme.primary.copy(alpha = 0.1f) else androidx.compose.ui.graphics.Color.Transparent
                    Row(Modifier.fillMaxWidth().background(tint).padding(vertical = 8.dp, horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text((index + 1).toString(), style = MaterialTheme.typography.titleMedium, modifier = Modifier.width(28.dp), textAlign = TextAlign.Center)
                        Avatar(row.userId, row.who, 36.dp)
                        Text(if (row.isMe) stringResource(R.string.you) else row.who, fontWeight = if (row.isMe) FontWeight.Bold else FontWeight.Normal, modifier = Modifier.weight(1f))
                        Text(format.format(row.value) + if (metric == "distance") " km" else "", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                if (rows.size <= 1) item { Text(stringResource(R.string.leaderboard_alone), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
        }
        item {
            Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.leaderboard_show_me), modifier = Modifier.weight(1f))
                Switch(
                    checked = shown ?: false, enabled = shown != null, modifier = Modifier.testTag("leaderboard-show"),
                    onCheckedChange = { value ->
                        val before = shown
                        shown = value
                        scope.launch { try { app.social.setShowsOnLeaderboard(me, value) } catch (e: ApiException) { shown = before } }
                    },
                )
            }
            Text(stringResource(R.string.leaderboard_show_me_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
