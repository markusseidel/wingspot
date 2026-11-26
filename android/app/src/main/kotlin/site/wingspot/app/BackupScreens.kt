package site.wingspot.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import site.wingspot.core.BackupCodec
import site.wingspot.core.BackupDocument
import site.wingspot.core.BackupException
import site.wingspot.core.BackupPreview
import site.wingspot.core.BackupResult
import site.wingspot.core.BackupService
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/**
 * A backup file picked in Settings or on the first screen, or opened into Wingspot from another app, waiting for the restore
 * review (#310). It waits because a file can arrive before the screen is there.
 */
object BackupInbox {
    var pending by mutableStateOf<Uri?>(null)

    /** A file Wingspot should treat as a backup: the name says so, or it is gzip and the name is not a KML. */
    fun looksLikeBackup(context: Context, uri: Uri): Boolean {
        if (uri.scheme != "content" && uri.scheme != "file") return false
        val name = if (uri.scheme == "file") uri.lastPathSegment else runCatching {
            context.contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { if (it.moveToFirst()) it.getString(0) else null }
        }.getOrNull()
        if (name?.lowercase()?.endsWith(".wingspotbackup") == true) return true
        if (name?.lowercase()?.endsWith(".kml") == true) return false
        val head = runCatching { context.contentResolver.openInputStream(uri)?.use { listOf(it.read(), it.read()) } }.getOrNull() ?: return false
        return head == listOf(0x1F, 0x8B)
    }
}

/** The file picker for a backup; the picked file goes to the restore review. */
@Composable
fun rememberBackupPicker(): () -> Unit {
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> if (uri != null) BackupInbox.pending = uri }
    return { launcher.launch(arrayOf("*/*")) }
}

/** Settings > Backup: make a backup file and share it, or pick one to restore. */
@Composable
fun BackupSection(app: WingspotApp) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val pick = rememberBackupPicker()
    var failed by remember { mutableStateOf(false) }
    Text(stringResource(R.string.backup_title), style = MaterialTheme.typography.titleMedium)
    Text(stringResource(R.string.backup_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    TextButton(onClick = {
        scope.launch {
            failed = !runCatching { share(app, context) }.isSuccess
        }
    }, modifier = Modifier.testTag("create-backup")) { Text(stringResource(R.string.backup_create)) }
    TextButton(onClick = pick, modifier = Modifier.testTag("restore-backup")) { Text(stringResource(R.string.backup_restore)) }
    if (failed) Text(stringResource(R.string.backup_create_failed), color = MaterialTheme.colorScheme.error)
}

/** Writes the backup into the cache, where only the share sheet can reach it, and opens the share sheet. The last one is replaced next time. */
private suspend fun share(app: WingspotApp, context: Context) {
    val uri = withContext(Dispatchers.IO) {
        val document = BackupService(app.checkIns, app.tracks).make("Wingspot ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
        val folder = File(context.cacheDir, "share/backup").also { it.deleteRecursively(); it.mkdirs() }
        val file = File(folder, "Wingspot-backup-${LocalDate.now()}.wingspotbackup")
        file.writeBytes(BackupCodec.encode(document))
        FileProvider.getUriForFile(context, "${context.packageName}.files", file)
    }
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "application/octet-stream"
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(send, null))
}

/** Reads a waiting backup file, says what it holds, and restores it when asked. Restore only adds (docs/BACKUP-PLAN.md). */
@Composable
fun BackupRestoreDialog(app: WingspotApp, signedIn: Boolean, onRestored: () -> Unit) {
    val uri = BackupInbox.pending ?: return
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var document by remember(uri) { mutableStateOf<BackupDocument?>(null) }
    var preview by remember(uri) { mutableStateOf<BackupPreview?>(null) }
    var problem by remember(uri) { mutableStateOf<BackupException?>(null) }
    var result by remember(uri) { mutableStateOf<BackupResult?>(null) }
    var replace by remember(uri) { mutableStateOf(false) }
    LaunchedEffect(uri) {
        try {
            val read = withContext(Dispatchers.IO) {
                val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: throw BackupException.Damaged
                BackupCodec.decode(bytes)
            }
            document = read
            preview = BackupService(app.checkIns, app.tracks).preview(read)
        } catch (e: BackupException) {
            problem = e
        } catch (e: Exception) {
            problem = BackupException.Damaged
        }
    }
    val close = { BackupInbox.pending = null }
    AlertDialog(
        onDismissRequest = close,
        title = { Text(stringResource(R.string.backup_restore_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                val done = result
                val failed = problem
                val shown = preview
                when {
                    done != null -> {
                        Text(resultLine(context, done), modifier = Modifier.testTag("backup-result"))
                        Text(stringResource(R.string.backup_keep_file), style = MaterialTheme.typography.bodySmall)
                    }
                    failed != null -> Text(stringResource(problemText(failed)), modifier = Modifier.testTag("backup-problem"))
                    shown != null -> {
                        Text(summary(context, shown), modifier = Modifier.testTag("backup-summary"))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Checkbox(checked = replace, onCheckedChange = { replace = it }, modifier = Modifier.testTag("backup-replace"))
                            Text(stringResource(R.string.backup_replace_routes))
                        }
                        if (shown.checkIns > 0 && signedIn) Text(stringResource(R.string.backup_added_to_account), style = MaterialTheme.typography.bodySmall)
                        if (shown.routes > 0 && shown.routesWithFlightHere == 0) {
                            Text(stringResource(R.string.backup_flights_not_here), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    else -> CircularProgressIndicator()
                }
            }
        },
        confirmButton = {
            if (result != null || problem != null) {
                TextButton(onClick = close) { Text(stringResource(R.string.done)) }
            } else {
                TextButton(enabled = document != null, onClick = {
                    val read = document ?: return@TextButton
                    scope.launch {
                        result = try {
                            withContext(Dispatchers.IO) { BackupService(app.checkIns, app.tracks).restore(read, replace) }
                        } catch (e: Exception) {
                            problem = BackupException.Damaged
                            null
                        }
                        if (result != null) {
                            OutboxWorker.schedule(context.applicationContext)
                            onRestored()
                        }
                    }
                }, modifier = Modifier.testTag("backup-do-restore")) { Text(stringResource(R.string.backup_restore_button)) }
            }
        },
        dismissButton = {
            if (result == null && problem == null) TextButton(onClick = close) { Text(stringResource(R.string.cancel)) }
        },
    )
}

private fun summary(context: Context, preview: BackupPreview): String {
    val date = preview.created?.atZone(ZoneId.systemDefault())?.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)) ?: "?"
    val source = context.getString(if (preview.platform == "ios") R.string.backup_from_iphone else R.string.backup_from_android)
    return context.getString(R.string.backup_summary, date, source, preview.routes, preview.checkIns)
}

private fun resultLine(context: Context, result: BackupResult): String {
    val line = context.getString(R.string.backup_restored, result.routes, result.checkIns)
    return if (result.skipped > 0) line + " " + context.getString(R.string.backup_skipped, result.skipped) else line
}

private fun problemText(problem: BackupException): Int = when (problem) {
    BackupException.NotBackup -> R.string.backup_not_backup
    BackupException.NewerVersion -> R.string.backup_newer_version
    BackupException.Damaged -> R.string.backup_damaged
}
