package site.wingspot.app

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import site.wingspot.core.ApiException
import site.wingspot.core.Person
import java.util.UUID

/** The most friends one check-in takes. The server cuts the list at the same number. */
const val MAX_TAGGED_FRIENDS = 8

/** The "With" row of a form: the friends who were with you, and a list to choose them from. */
@Composable
fun WithFriendsField(selected: List<Person>, onChange: (List<Person>) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().clickable { open = true }.testTag("with-friends"),
        horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(stringResource(R.string.with_label))
        Text(
            (if (selected.isEmpty()) stringResource(R.string.optional) else selected.joinToString(", ") { it.who }) + " ›",
            color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(vertical = 12.dp),
        )
    }
    if (open) FriendPickerDialog(selected, onChange) { open = false }
}

/** Your mutual friends, to choose the ones who were with you. They get to see the check-in. */
@Composable
private fun FriendPickerDialog(selected: List<Person>, onChange: (List<Person>) -> Unit, onClose: () -> Unit) {
    val app = LocalContext.current.applicationContext as WingspotApp
    // null while loading, the friends once loaded, and an empty answer with `failed` when the request failed.
    val loaded by produceState<Pair<List<Person>, Boolean>?>(null) {
        value = try { app.social.taggableFriends() to false } catch (e: ApiException) { emptyList<Person>() to true }
    }
    val friends = loaded?.first.orEmpty()
    // People already chosen stay in the list, even if they can no longer be tagged, so they can be taken off.
    val everyone = friends + selected.filter { chosen -> friends.none { it.id == chosen.id } }
    var search by remember { mutableStateOf("") }
    val query = search.trim()
    // The friends you flew with most often, from the check-ins on this phone.
    val local = LocalCheckIns.current
    val often = remember(local, everyone) {
        val counts = local.flatMap { it.taggedIds.orEmpty() }.groupingBy { it.toString() }.eachCount()
        everyone.filter { (counts[it.id] ?: 0) > 0 }.sortedWith(compareByDescending<Person> { counts[it.id] ?: 0 }.thenBy { it.who }).take(3)
    }
    val atLimit = selected.size >= MAX_TAGGED_FRIENDS
    @Composable
    fun FriendRow(friend: Person) {
        val chosen = selected.any { it.id == friend.id }
        Row(
            Modifier.fillMaxWidth().clickable(enabled = chosen || !atLimit) {
                onChange(if (chosen) selected.filterNot { it.id == friend.id } else selected + friend)
            }.padding(vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Checkbox(checked = chosen, onCheckedChange = null, enabled = chosen || !atLimit)
            Text(friend.who, modifier = Modifier.padding(start = 8.dp))
        }
    }
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text(stringResource(R.string.with_label)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = search, onValueChange = { search = it }, modifier = Modifier.fillMaxWidth().testTag("friend-search"),
                    placeholder = { Text(stringResource(R.string.search_friends)) }, singleLine = true,
                )
                when {
                    loaded == null -> Text(stringResource(R.string.loading))
                    loaded?.second == true -> Text(stringResource(R.string.with_failed))
                    everyone.isEmpty() -> Text(stringResource(R.string.with_no_friends))
                    query.isNotEmpty() -> {
                        val found = everyone.filter { it.who.contains(query, ignoreCase = true) || it.username.contains(query, ignoreCase = true) }
                        if (found.isEmpty()) Text(stringResource(R.string.no_results), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        else LazyColumn { items(found, key = { it.id }) { FriendRow(it) } }
                    }
                    else -> LazyColumn {
                        if (often.isNotEmpty()) {
                            item { SectionHeader(stringResource(R.string.friends_often), Modifier.padding(top = 4.dp)) }
                            items(often, key = { "often-" + it.id }) { FriendRow(it) }
                            item { SectionHeader(stringResource(R.string.friends_all), Modifier.padding(top = 8.dp)) }
                        }
                        items(everyone.filter { f -> often.none { it.id == f.id } }, key = { it.id }) { FriendRow(it) }
                        item { Text(stringResource(R.string.with_footer, MAX_TAGGED_FRIENDS), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 8.dp)) }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onClose) { Text(stringResource(R.string.done)) } },
    )
}

/** The friends chosen on a form. For an existing check-in, [initial] holds the ones it has now, once they are loaded. */
class TagChoice {
    var initial by mutableStateOf<List<Person>?>(null)
    var chosen by mutableStateOf(emptyList<Person>())

    /** Everyone chosen, for a new check-in. */
    fun all(): List<UUID> = chosen.map { UUID.fromString(it.id) }

    /** The choice for an edit: null while it is unchanged, so friends tagged on another device stay. */
    fun ifChanged(): List<UUID>? = if (initial != null && chosen.map { it.id } != initial!!.map { it.id }) all() else null
}

/** A form's choice of friends. Pass the id of a saved check-in to start from the friends it has. */
@Composable
fun rememberTagChoice(checkIn: UUID? = null): TagChoice {
    val app = LocalContext.current.applicationContext as WingspotApp
    val choice = remember { TagChoice() }
    LaunchedEffect(checkIn) {
        if (checkIn == null) {
            choice.initial = emptyList()
        } else {
            val found = runCatching { app.social.tags(listOf(checkIn.toString()))[checkIn.toString()].orEmpty() }.getOrNull()
            choice.initial = found
            choice.chosen = found.orEmpty()
        }
    }
    return choice
}

/** The "With" row for a form. Hidden for a saved check-in until its friends are loaded, so a failed load can't wipe them. */
@Composable
fun WithFriendsField(choice: TagChoice) {
    if (choice.initial != null) WithFriendsField(choice.chosen) { choice.chosen = it }
}
