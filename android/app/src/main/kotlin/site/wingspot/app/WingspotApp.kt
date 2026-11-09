package site.wingspot.app

import android.app.Application
import java.io.File
import site.wingspot.core.ApiClient
import site.wingspot.core.ApiException
import site.wingspot.core.AuthException
import site.wingspot.core.CheckInStore
import site.wingspot.core.Outbox
import site.wingspot.core.ReferenceDataInstaller
import site.wingspot.core.SupabaseAuth

/** The pieces the screens and the background upload share. */
class WingspotApp : Application() {
    val sessions by lazy { SessionStore(this) }
    val auth by lazy { SupabaseAuth(BuildConfig.SUPABASE_URL, BuildConfig.PUBLISHABLE_KEY) }
    val checkIns by lazy { CheckInStore.open(File(filesDir, "checkins.sqlite").path) }
    val referenceInstaller by lazy { ReferenceDataInstaller(File(filesDir, "refdata"), BuildConfig.SUPABASE_URL + "/functions") }
    val outbox by lazy { Outbox(checkIns, ApiClient(BuildConfig.SUPABASE_URL + "/functions"), ::accessToken) }

    /** A valid access token, refreshed when it is about to expire or after the server refused it. Null if signed out. */
    private suspend fun accessToken(forceRefresh: Boolean): String? {
        val session = sessions.load() ?: return null
        if (!forceRefresh && !sessions.expiresSoon()) return session.accessToken
        return try {
            val fresh = auth.refresh(session.refreshToken)
            sessions.save(fresh)
            fresh.accessToken
        } catch (e: AuthException.Offline) {
            throw ApiException.Retry
        } catch (e: AuthException.Unknown) {
            throw ApiException.Retry
        } catch (e: AuthException) {
            // The refresh token itself was refused: the session is over.
            sessions.clear()
            null
        }
    }
}
