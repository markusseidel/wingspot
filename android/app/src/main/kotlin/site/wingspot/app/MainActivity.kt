package site.wingspot.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.activity.compose.setContent
import kotlinx.coroutines.launch
import androidx.lifecycle.lifecycleScope
import androidx.activity.viewModels
import androidx.compose.material3.Surface
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

class MainActivity : ComponentActivity() {
    private val model: AppViewModel by viewModels { AppViewModel.factory(application as WingspotApp) }
    private val checkIn: CheckInViewModel by viewModels { CheckInViewModel.factory(application as WingspotApp) }
    private val announcements: AnnouncementsViewModel by viewModels { AnnouncementsViewModel.factory(application as WingspotApp) }
    private val social: SocialViewModel by viewModels { SocialViewModel.factory(application as WingspotApp) }
    private val badges: BadgesViewModel by viewModels { BadgesViewModel.factory(application as WingspotApp) }
    private val reference: ReferenceViewModel by viewModels { ReferenceViewModel.factory(application as WingspotApp) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handle(intent)
        OutboxWorker.schedule(applicationContext) // sends whatever was left from last time
        Push.register(application as WingspotApp)
        lifecycleScope.launch { (application as WingspotApp).refreshKmlSwitches() }
        // The long-press entry for the running spotting session follows the session, and is checked again when the app comes back.
        lifecycleScope.launch { repeatOnLifecycle(Lifecycle.State.STARTED) { checkIn.state.map { it.session }.distinctUntilChanged().collect { QuickShortcuts.showSession(applicationContext, it) } } }
        setContent {
            WingspotTheme {
                Surface { AppScreen(application as WingspotApp, model, reference, checkIn, social, badges, announcements) }
            }
        }
    }

    /** The KML file an intent hands over (a view or a share), or null for anything else. */
    private fun incomingKml(intent: Intent?): android.net.Uri? {
        if (intent == null || !(application as WingspotApp).prefs.kmlImportOn) return null
        val uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> if (android.os.Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, android.net.Uri::class.java) else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        } ?: return null
        if (uri.scheme != "content" && uri.scheme != "file") return null
        val name = if (uri.scheme == "file") uri.lastPathSegment else contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null }
        return uri.takeIf { site.wingspot.core.KmlFile.looksLikeKml(intent.type ?: contentResolver.getType(uri), name ?: uri.lastPathSegment) }
    }

    // The sign-in link opens this activity again (singleTask) instead of starting a second one.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        // A KML file shared or opened from another app opens the flight form, which reads it (#236). Only when the import is switched on.
        incomingKml(intent)?.let { uri ->
            social.stack.clear()
            checkIn.openKmlFile(uri)
            return
        }
        // A shortcut of a long press on the app icon opens its form straight away (#349).
        site.wingspot.core.QuickAction.parse(intent?.getStringExtra("quick_action"))?.let {
            social.stack.clear()
            checkIn.openKind(QuickShortcuts.kind(it))
        }
        // A notification carries what it is about in its extras: open that screen.
        val extras = listOf("type", "checkin", "actor").associateWith { intent?.getStringExtra(it) }
        Push.destination(extras)?.let { (kind, id) ->
            social.tab = Tab.FEED
            when (kind) {
                "person" -> social.openPerson(id)
                "review" -> social.stack.add(Route.ReviewSpots)
                else -> social.stack.add(Route.CheckInPage(id))
            }
        }
        val link = intent?.data?.toString() ?: return
        if (link.startsWith("wingspot://auth-callback")) model.completeSignIn(link)
        else site.wingspot.core.InviteLink.code(link)?.let(social::receiveInvite)
    }
}
