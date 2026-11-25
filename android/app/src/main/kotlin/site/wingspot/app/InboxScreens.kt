package site.wingspot.app

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import site.wingspot.core.SocialApi

/** The activity inbox: followers, salutes, comments, tags and alerts, newest first. */
@Composable
fun InboxPage(app: WingspotApp, model: SocialViewModel, checkIn: CheckInViewModel) {
    LaunchedEffect(Unit) { model.loadInbox(); model.loadCompanionRequests() }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    Column(Modifier.fillMaxWidth().testTag("inbox"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = model::back) { Text("‹ " + stringResource(R.string.back)) }
            Text(stringResource(R.string.activity_title), style = MaterialTheme.typography.titleLarge)
            Box(Modifier.weight(1f))
            TextButton(onClick = model::markAllRead, enabled = model.inboxHasUnread, modifier = Modifier.testTag("mark-all-read")) { Text(stringResource(R.string.activity_mark_all_read)) }
        }
        when {
            !model.inboxLoaded -> CircularProgressIndicator(Modifier.padding(16.dp))
            model.inboxFailed && model.inbox.isEmpty() -> {
                Text(stringResource(R.string.activity_failed), color = MaterialTheme.colorScheme.error)
                TextButton(onClick = model::loadInbox) { Text(stringResource(R.string.refresh)) }
            }
            model.inbox.isEmpty() && model.companionRequests.isEmpty() -> {
                Text(stringResource(R.string.activity_empty_title), style = MaterialTheme.typography.titleMedium)
                Text(stringResource(R.string.activity_empty), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            else -> LazyColumn(Modifier.fillMaxWidth()) {
                if (model.companionRequests.isNotEmpty()) {
                    item(key = "companion-title") { Text(stringResource(R.string.companion_requests_title), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(vertical = 8.dp)) }
                    items(model.companionRequests, key = { "companion-" + it.checkInId }) { request ->
                        CompanionRequestRow(
                            request,
                            onAccept = { scope.launch { app.social.checkIn(request.checkInId)?.let(checkIn::acceptFromFriend) } },
                            onDecline = { model.declineRequest(request.checkInId) },
                        )
                        HorizontalDivider()
                    }
                }
                items(model.inbox, key = { it.id }) { row ->
                    InboxRow(row, onClick = {
                        model.markInboxRowRead(row)
                        when {
                            row.kind == "follow" -> model.openPerson(row.actorId)
                            row.kind == "spot_proposed" -> model.open(Route.ReviewSpots)
                            row.checkInId != null -> model.stack.add(Route.CheckInPage(row.checkInId!!))
                        }
                    })
                    HorizontalDivider()
                    if (row.id == model.inbox.lastOrNull()?.id) LaunchedEffect(row.id) { model.loadMoreInbox() }
                }
            }
        }
    }
}

@Composable
private fun InboxRow(row: SocialApi.ActivityItem, onClick: () -> Unit) {
    val unreadTint = if (row.isRead) androidx.compose.ui.graphics.Color.Transparent else MaterialTheme.colorScheme.primary.copy(alpha = 0.2f)
    Row(
        Modifier.fillMaxWidth().background(unreadTint).clickable(onClick = onClick).padding(vertical = 10.dp, horizontal = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // A dot for what is unread: a tint alone is hard to see in dark mode.
        Box(Modifier.padding(top = 16.dp).size(8.dp).background(if (row.isRead) androidx.compose.ui.graphics.Color.Transparent else MaterialTheme.colorScheme.primary, CircleShape))
        Avatar(row.actorId, row.who, 40.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(sentence(row), style = MaterialTheme.typography.bodyMedium)
            if (row.kind == "spot_rejected" && row.snippet.orEmpty().contains('\n')) {
                Text(row.snippet.orEmpty().substringAfter('\n'), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 3)
            }
            if ((row.kind == "comment" || row.kind == "mention") && !row.snippet.isNullOrBlank()) {
                Text("\u201C${row.snippet}\u201D", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
            }
            Text(relativeTime(row.createdAt), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** One sentence that starts with who did it, the name in bold. */
@Composable
private fun sentence(row: SocialApi.ActivityItem): AnnotatedString {
    val spotKind = row.kind == "spot_approved" || row.kind == "spot_rejected"
    val name = if (spotKind) row.snippet.orEmpty().lineSequence().first() else row.who
    val subject = row.subject
    val text = when (row.kind) {
        "spot_proposed" -> stringResource(R.string.activity_spot_proposed, name, row.snippet.orEmpty().lineSequence().first())
        "spot_approved" -> stringResource(R.string.activity_spot_approved, name)
        "spot_rejected" -> stringResource(R.string.activity_spot_rejected, name)
        "follow" -> stringResource(R.string.activity_follow, name)
        "salute" -> if (subject != null) stringResource(R.string.activity_salute_on, name, subject) else stringResource(R.string.activity_salute, name)
        "comment" -> if (subject != null) stringResource(R.string.activity_comment_on, name, subject) else stringResource(R.string.activity_comment, name)
        "tagged" -> if (subject != null) stringResource(R.string.activity_tagged_on, name, subject) else stringResource(R.string.activity_tagged, name)
        "checkin" -> if (subject != null) stringResource(R.string.activity_checkin_on, name, subject) else stringResource(R.string.activity_checkin, name)
        "tag_copy" -> if (subject != null) stringResource(R.string.activity_tag_copy_on, name, subject) else stringResource(R.string.activity_tag_copy, name)
        "mention" -> stringResource(R.string.activity_mention, name)
        "comment_like" -> stringResource(R.string.activity_comment_like, name)
        else -> stringResource(R.string.activity_other, name)
    }
    return buildAnnotatedString {
        val at = text.indexOf(name)
        if (at < 0) { append(text); return@buildAnnotatedString }
        append(text.substring(0, at))
        withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(name) }
        append(text.substring(at + name.length))
    }
}
