package site.wingspot.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface

class MainActivity : ComponentActivity() {
    private val model: AppViewModel by viewModels { AppViewModel.factory(application as WingspotApp) }
    private val checkIn: CheckInViewModel by viewModels { CheckInViewModel.factory(application as WingspotApp) }
    private val reference: ReferenceViewModel by viewModels { ReferenceViewModel.factory(application as WingspotApp) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handle(intent)
        OutboxWorker.schedule(applicationContext) // sends whatever was left from last time
        setContent {
            MaterialTheme {
                Surface { AppScreen(model, reference, checkIn) }
            }
        }
    }

    // The sign-in link opens this activity again (singleTask) instead of starting a second one.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        val link = intent?.data?.toString() ?: return
        if (link.startsWith("wingspot://auth-callback")) model.completeSignIn(link)
    }
}
