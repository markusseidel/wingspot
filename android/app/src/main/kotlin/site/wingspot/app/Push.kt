package site.wingspot.app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import site.wingspot.core.ApiException

/** Push notifications through Firebase. Everything here does nothing unless the build has the Firebase project's file. */
object Push {
    const val CHANNEL = "wingspot_activity"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** False in a build made without google-services.json: there is nothing to register with. */
    fun isAvailable(context: Context): Boolean = FirebaseApp.getApps(context).isNotEmpty()

    /** True when the phone lets the app show notifications (always on Android 12 and older). */
    fun isAllowed(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun createChannel(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, context.getString(R.string.channel_name), NotificationManager.IMPORTANCE_DEFAULT),
        )
    }

    /**
     * Tells the server this phone's token, when the person is signed in, notifications are allowed and Firebase is set
     * up. Safe to call often: the server keeps one row per device.
     */
    fun register(app: WingspotApp) {
        if (!isAvailable(app) || !isAllowed(app) || app.sessions.load() == null) return
        scope.launch {
            try {
                val token = FirebaseMessaging.getInstance().token.await()
                app.social.registerDevice(app.prefs.deviceId(), BuildConfig.VERSION_NAME, token, Build.VERSION.RELEASE, Locale.getDefault().language)
            } catch (e: ApiException) {
                // Offline or signed out: the next start tries again.
            } catch (e: Exception) {
            }
        }
    }

    /** Stops notifications for this phone's account, while the session still works. */
    suspend fun unregister(app: WingspotApp) {
        try {
            app.social.removeDevice(app.prefs.deviceId())
        } catch (e: Exception) {
        }
    }

    /** The screen a notification opens, from what the server put in it. Null if it names nothing we can open. */
    fun destination(extras: Map<String, String?>): Pair<String, String>? {
        val type = extras["type"] ?: return null
        return when (type) {
            "follow" -> extras["actor"]?.takeIf { it.isNotBlank() }?.let { "person" to it }
            else -> extras["checkin"]?.takeIf { it.isNotBlank() }?.let { "checkin" to it }
        }
    }
}

private suspend fun <T> com.google.android.gms.tasks.Task<T>.await(): T = suspendCancellableCoroutine { cont ->
    addOnSuccessListener { cont.resumeWith(Result.success(it)) }
    addOnFailureListener { cont.resumeWith(Result.failure(it)) }
}

/** Receives the token and the messages. A message that arrives while the app is open is shown here; others the phone shows itself. */
class PushService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        Push.register(application as WingspotApp)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val notification = message.notification ?: return
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            for ((k, v) in message.data) putExtra(k, v)
        }
        val pending = PendingIntent.getActivity(this, message.messageId.hashCode(), intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val built = NotificationCompat.Builder(this, Push.CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_wingspot).setContentTitle(notification.title).setContentText(notification.body)
            .setAutoCancel(true).setContentIntent(pending).build()
        if (Push.isAllowed(this)) (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(message.messageId.hashCode(), built)
    }
}
