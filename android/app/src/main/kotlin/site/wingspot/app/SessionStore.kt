package site.wingspot.app

import android.content.Context
import site.wingspot.core.Session
import site.wingspot.core.SessionUser

/**
 * Keeps the session on the phone. The spike uses private app storage; before release the tokens move into
 * the Android Keystore (docs/ANDROID.md, step A0).
 */
class SessionStore(context: Context) {
    private val prefs = context.getSharedPreferences("session", Context.MODE_PRIVATE)

    fun load(): Session? {
        val access = prefs.getString("access", null) ?: return null
        val refresh = prefs.getString("refresh", null) ?: return null
        val id = prefs.getString("user_id", null) ?: return null
        return Session(access, refresh, 3600, SessionUser(id, prefs.getString("email", null)))
    }

    fun save(session: Session) {
        prefs.edit()
            .putString("access", session.accessToken).putString("refresh", session.refreshToken)
            .putString("user_id", session.user.id).putString("email", session.user.email).apply()
    }

    fun clear() = prefs.edit().clear().apply()

    /** The PKCE verifier waits here while the email is on its way, as the app may be stopped meanwhile. */
    fun saveVerifier(verifier: String) = prefs.edit().putString("verifier", verifier).apply()
    fun verifier(): String? = prefs.getString("verifier", null)
}
