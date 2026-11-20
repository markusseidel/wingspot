package site.wingspot.app

import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import kotlinx.coroutines.launch
import site.wingspot.core.ApiException
import site.wingspot.core.InviteLink
import site.wingspot.core.SocialApi

/** Invite friends: share your code, link and QR code, add someone by their code, and follow people you may know. */
@Composable
fun InvitePage(app: WingspotApp, model: SocialViewModel, me: String) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var code by remember { mutableStateOf<String?>(null) }
    var typed by remember { mutableStateOf("") }
    var message by remember { mutableStateOf<String?>(null) }
    var suggestions by remember { mutableStateOf(emptyList<SocialApi.Suggestion>()) }
    var followed by remember { mutableStateOf(emptySet<String>()) }
    var allow by remember { mutableStateOf<Boolean?>(null) }
    var confirmReset by remember { mutableStateOf(false) }
    val followedText = stringResource(R.string.invite_you_follow)
    val noMatch = stringResource(R.string.invite_no_match)
    LaunchedEffect(me) {
        code = runCatching { app.social.myInviteCode() }.getOrNull()
        suggestions = runCatching { app.social.suggestions() }.getOrDefault(emptyList())
        allow = runCatching { app.social.allowsSuggestions(me) }.getOrNull()
    }
    LazyColumn(Modifier.fillMaxWidth().testTag("invite"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = model::back) { Text("‹ " + stringResource(R.string.back)) }
                Text(stringResource(R.string.invite_title), style = MaterialTheme.typography.titleLarge)
            }
        }
        item {
            Text(stringResource(R.string.invite_your_code), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            val c = code
            if (c != null) {
                Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(c, style = MaterialTheme.typography.headlineSmall, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f).testTag("invite-code"))
                    Button(onClick = {
                        val text = context.getString(R.string.invite_share_text, c, InviteLink.url(c))
                        val send = Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }
                        context.startActivity(Intent.createChooser(send, null))
                    }) { Text(stringResource(R.string.invite_share)) }
                }
                val qr = remember(c) { qrBitmap(InviteLink.url(c), 512) }
                Box(Modifier.fillMaxWidth().padding(top = 12.dp), contentAlignment = Alignment.Center) {
                    Image(qr.asImageBitmap(), contentDescription = stringResource(R.string.invite_qr), modifier = Modifier.size(200.dp))
                }
                Text(stringResource(R.string.invite_your_code_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 8.dp))
            }
        }
        item {
            Text(stringResource(R.string.invite_add_by_code), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(typed, { typed = it }, modifier = Modifier.weight(1f).testTag("invite-typed"), singleLine = true, placeholder = { Text(stringResource(R.string.invite_code_hint)) })
                Button(enabled = InviteLink.clean(typed) != null, modifier = Modifier.testTag("invite-follow"), onClick = {
                    val clean = InviteLink.clean(typed) ?: return@Button
                    scope.launch {
                        val person = try { app.social.followByCode(clean) } catch (e: ApiException) { null }
                        message = if (person != null) followedText.replace("%s", person.who) else noMatch
                        if (person != null) typed = ""
                    }
                }) { Text(stringResource(R.string.follow)) }
            }
            message?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        if (suggestions.isNotEmpty()) {
            item { Text(stringResource(R.string.invite_may_know), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold) }
            items(suggestions, key = { it.userId }) { person ->
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Avatar(person.userId, person.who, 36.dp)
                    androidx.compose.foundation.layout.Column(Modifier.weight(1f)) {
                        Text(person.who)
                        Text(
                            if (person.reason == "tagged") stringResource(R.string.invite_reason_tagged) else stringResource(R.string.invite_reason_mutual, person.mutual),
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (person.userId in followed) Text(stringResource(R.string.following), style = MaterialTheme.typography.bodySmall)
                    else OutlinedButton(onClick = {
                        followed = followed + person.userId
                        scope.launch { try { app.social.follow(person.userId, me) } catch (e: ApiException) { followed = followed - person.userId } }
                    }) { Text(stringResource(R.string.follow)) }
                }
            }
        }
        item {
            Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.invite_suggest_me), modifier = Modifier.weight(1f))
                Switch(checked = allow ?: true, enabled = allow != null, modifier = Modifier.testTag("invite-suggest"), onCheckedChange = { value ->
                    val before = allow
                    allow = value
                    scope.launch { try { app.social.setAllowsSuggestions(me, value) } catch (e: ApiException) { allow = before } }
                })
            }
            TextButton(onClick = { confirmReset = true }) { Text(stringResource(R.string.invite_new_code), color = MaterialTheme.colorScheme.error) }
            Text(stringResource(R.string.invite_new_code_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    if (confirmReset) AlertDialog(
        onDismissRequest = { confirmReset = false },
        title = { Text(stringResource(R.string.invite_new_code_title)) },
        text = { Text(stringResource(R.string.invite_new_code_message)) },
        confirmButton = { TextButton(onClick = { confirmReset = false; scope.launch { code = runCatching { app.social.resetInviteCode() }.getOrDefault(code) } }) { Text(stringResource(R.string.invite_new_code), color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = { confirmReset = false }) { Text(stringResource(R.string.cancel)) } },
    )
}

/** A QR code of some text as a black and white picture. */
private fun qrBitmap(text: String, size: Int): Bitmap {
    val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size, mapOf(com.google.zxing.EncodeHintType.MARGIN to 1))
    val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    for (x in 0 until size) for (y in 0 until size) bitmap.setPixel(x, y, if (matrix.get(x, y)) 0xFF000000.toInt() else 0xFFFFFFFF.toInt())
    return bitmap
}
