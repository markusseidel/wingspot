package site.wingspot.app

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import site.wingspot.core.BadgeFilter
import site.wingspot.core.BadgeProgress
import site.wingspot.core.Rank
import site.wingspot.core.UserProgress

private val CATEGORY_ORDER = listOf("milestones", "airports", "countries", "types", "time", "hidden")

/** The languages of the phone, most preferred first, for badge texts. */
@Composable
private fun languages(): List<String> {
    val locales = LocalConfiguration.current.locales
    return (0 until locales.size()).map { locales[it].language }
}

/** The Badges tab: level and XP on top, then every badge with its progress. */
@Composable
fun BadgesTab(model: BadgesViewModel, signedIn: Boolean, onSignIn: () -> Unit) {
    val state by model.state.collectAsState()
    var filter by remember { mutableStateOf(BadgeFilter.ALL) }
    val progress = state.progress
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.tab_badges), style = MaterialTheme.typography.headlineMedium, modifier = Modifier.padding(top = 16.dp))
        when {
            !signedIn -> {
                Text(stringResource(R.string.badges_sign_in))
                Button(onClick = onSignIn) { Text(stringResource(R.string.sign_in_title)) }
            }
            progress != null -> BadgeList(progress, filter, { filter = it }, model::refresh)
            state.refreshFailed -> {
                Text(stringResource(R.string.badges_failed), color = MaterialTheme.colorScheme.error)
                OutlinedButton(onClick = model::refresh) { Text(stringResource(R.string.try_again)) }
            }
            else -> Text(stringResource(R.string.loading))
        }
    }
}

@Composable
private fun BadgeList(progress: UserProgress, filter: BadgeFilter, onFilter: (BadgeFilter) -> Unit, onRefresh: () -> Unit) {
    val groups = run {
        val categories = CATEGORY_ORDER + progress.badges.map { it.category }.distinct().filter { it !in CATEGORY_ORDER }.sorted()
        categories.mapNotNull { category -> progress.badges.filter { it.category == category && filter.matches(it) }.takeIf { it.isNotEmpty() }?.let { category to it } }
    }
    LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item { LevelHeader(progress) }
        item { Text(stringResource(R.string.badges_earned, progress.earnedCount, progress.badges.size), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        item {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for ((value, label) in listOf(BadgeFilter.ALL to R.string.filter_all, BadgeFilter.EARNED to R.string.filter_earned, BadgeFilter.IN_PROGRESS to R.string.filter_in_progress)) {
                    FilterChip(selected = filter == value, onClick = { onFilter(value) }, label = { Text(stringResource(label)) })
                }
            }
        }
        for ((category, badges) in groups) {
            item(key = "h-$category") { Text(categoryTitle(category), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp)) }
            items(badges, key = { it.id }) { BadgeRow(it) }
            if (category == "hidden" && progress.hiddenRemaining > 0) {
                item(key = "hidden-left") { Text(stringResource(R.string.hidden_left, progress.hiddenRemaining), color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
        }
        if (groups.isEmpty()) item { Text(stringResource(R.string.no_badges_here), color = MaterialTheme.colorScheme.onSurfaceVariant) }
        if (filter == BadgeFilter.ALL && progress.hiddenRemaining > 0 && progress.badges.none { it.category == "hidden" }) {
            item { Text(stringResource(R.string.hidden_left, progress.hiddenRemaining), color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        item { TextButton(onClick = onRefresh) { Text(stringResource(R.string.refresh)) } }
    }
}

@Composable
private fun categoryTitle(category: String): String = stringResource(
    when (category) {
        "milestones" -> R.string.cat_milestones
        "airports" -> R.string.cat_airports
        "countries" -> R.string.cat_countries
        "types" -> R.string.cat_types
        "time" -> R.string.cat_time
        "hidden" -> R.string.cat_hidden
        else -> return category.replaceFirstChar { it.uppercase() }
    },
)

@Composable
fun LevelHeader(progress: UserProgress) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(stringResource(R.string.level_n, progress.level), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text("  " + stringResource(rankTitle(Rank.of(progress.level))), color = MaterialTheme.colorScheme.onSurfaceVariant)
            Box(Modifier.weight(1f))
            Text("${progress.xp} XP", style = MaterialTheme.typography.titleMedium)
        }
        LinearProgressIndicator(progress = { progress.levelFraction }, modifier = Modifier.fillMaxWidth())
        Text(
            stringResource(R.string.xp_to_next, maxOf(0, progress.xpForNextLevel - progress.xp), progress.level + 1),
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private fun rankTitle(rank: Rank) = when (rank) {
    Rank.CADET -> R.string.rank_cadet
    Rank.STUDENT_PILOT -> R.string.rank_student_pilot
    Rank.FIRST_OFFICER -> R.string.rank_first_officer
    Rank.CAPTAIN -> R.string.rank_captain
    Rank.SENIOR_CAPTAIN -> R.string.rank_senior_captain
    Rank.CHIEF_PILOT -> R.string.rank_chief_pilot
    Rank.ACE -> R.string.rank_ace
    Rank.LEGEND -> R.string.rank_legend
}

/** Grey while locked, then bronze, silver and gold as the levels fill up. */
private fun badgeColor(level: Int, of: Int): Color {
    if (level <= 0 || of <= 0) return Color(0x80808080)
    val fraction = level.toFloat() / of
    return when {
        fraction >= 1f -> Color(0xFFFFCC00)
        fraction > 0.5f -> Color(0xFF9E9EA3)
        else -> Color(0xFFA2845E)
    }
}

private fun symbol(category: String) = when (category) {
    "milestones" -> "🏁"; "airports" -> "🛬"; "countries" -> "🌍"; "types" -> "✈️"; "time" -> "🕐"; "hidden" -> "✨"; else -> "🎖"
}

@Composable
private fun BadgeIcon(badge: BadgeProgress, size: Int = 44) {
    Box(Modifier.size(size.dp).clip(CircleShape).background(badgeColor(badge.level, badge.levels.size)), contentAlignment = Alignment.Center) {
        Text(symbol(badge.category), style = MaterialTheme.typography.titleMedium)
    }
}

@Composable
private fun BadgeRow(badge: BadgeProgress) {
    val langs = languages()
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        BadgeIcon(badge)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(badge.title(langs), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            badge.text(langs)?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            val target = badge.nextTarget
            if (target != null) {
                LinearProgressIndicator(progress = { (minOf(badge.value, target).toFloat() / target) }, modifier = Modifier.fillMaxWidth())
                Row {
                    if (!badge.isSingle) Text(stringResource(R.string.badge_level_of, badge.level, badge.levels.size), style = MaterialTheme.typography.labelSmall)
                    Box(Modifier.weight(1f))
                    Text("${badge.value} / $target", style = MaterialTheme.typography.labelSmall)
                }
            } else {
                Text("✓ " + stringResource(if (badge.isSingle) R.string.badge_unlocked else R.string.badge_all_levels), style = MaterialTheme.typography.bodySmall, color = Color(0xFF34C759))
            }
        }
    }
}

/** Shown once for each new unlock, until the person closes it. */
@Composable
fun CelebrationDialog(model: BadgesViewModel) {
    val state by model.state.collectAsState()
    if (state.celebrations.isEmpty()) return
    val langs = languages()
    AlertDialog(
        onDismissRequest = model::acknowledge,
        title = { Text(stringResource(R.string.celebration_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                for (c in state.celebrations) Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    BadgeIcon(c.badge, 52)
                    Column {
                        Text(c.badge.title(langs), fontWeight = FontWeight.Bold)
                        if (!c.badge.isSingle) Text(stringResource(R.string.badge_level_of, c.badge.level, c.badge.levels.size), style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = model::acknowledge) { Text(stringResource(R.string.great)) } },
    )
}
