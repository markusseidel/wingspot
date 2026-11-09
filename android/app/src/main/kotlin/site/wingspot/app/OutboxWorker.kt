package site.wingspot.app

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit
import site.wingspot.core.SyncOutcome

/** Uploads the check-ins that are waiting. Android runs it when there is a network and retries with a growing delay. */
class OutboxWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result =
        when ((applicationContext as WingspotApp).outbox.sync()) {
            is SyncOutcome.Done -> Result.success()
            // Nobody is signed in: the sign-in schedules this again.
            SyncOutcome.SignedOut -> Result.success()
            SyncOutcome.RetryLater -> Result.retry()
        }

    companion object {
        private const val NAME = "outbox"

        /** Asks for an upload soon. Several requests in a row collapse into one run. */
        fun schedule(context: Context) {
            val request = OneTimeWorkRequestBuilder<OutboxWorker>()
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(NAME, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
        }
    }
}
