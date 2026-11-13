package site.wingspot.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.material3.Surface

class MainActivity : ComponentActivity() {
    private val model: AppViewModel by viewModels { AppViewModel.factory(application as WingspotApp) }
    private val checkIn: CheckInViewModel by viewModels { CheckInViewModel.factory(application as WingspotApp) }
    private val social: SocialViewModel by viewModels { SocialViewModel.factory(application as WingspotApp) }
    private val badges: BadgesViewModel by viewModels { BadgesViewModel.factory(application as WingspotApp) }
    private val reference: ReferenceViewModel by viewModels { ReferenceViewModel.factory(application as WingspotApp) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handle(intent)
        OutboxWorker.schedule(applicationContext) // sends whatever was left from last time
        Push.register(application as WingspotApp)
        setContent {
            WingspotTheme {
                Surface { AppScreen(application as WingspotApp, model, reference, checkIn, social, badges) }
            }
        }
    }

    // The sign-in link opens this activity again (singleTask) instead of starting a second one.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        // A notification carries what it is about in its extras: open that screen.
        val extras = listOf("type", "checkin", "actor").associateWith { intent?.getStringExtra(it) }
        Push.destination(extras)?.let { (kind, id) ->
            social.tab = Tab.FEED
            if (kind == "person") social.openPerson(id) else social.stack.add(Route.CheckInPage(id))
        }
        val link = intent?.data?.toString() ?: return
        if (link.startsWith("wingspot://auth-callback")) model.completeSignIn(link)
    }
}
