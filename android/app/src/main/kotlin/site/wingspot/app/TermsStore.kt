package site.wingspot.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import site.wingspot.core.TermsMemory
import site.wingspot.core.TermsRemote
import site.wingspot.core.TermsSync

/**
 * Whether this person has accepted the community rules: kept on the phone per account, so the app starts offline, and with
 * the account on the server, so a second phone or a reinstall doesn't ask again (docs/MINIMUM-AGE-PLAN.md). Raise
 * `CURRENT_TERMS_VERSION` in core when the rules change.
 */
class TermsStore(context: Context, remote: TermsRemote) {
    private val prefs = context.getSharedPreferences("terms", Context.MODE_PRIVATE)
    private val memory = object : TermsMemory {
        override fun version(user: String) = prefs.getInt(user, 0)
        override fun setVersion(user: String, version: Int) = prefs.edit().putInt(user, version).apply()
        override fun isPending(user: String) = prefs.getBoolean("pending.$user", false)
        override fun setPending(user: String, pending: Boolean) = prefs.edit().putBoolean("pending.$user", pending).apply()
    }
    private val sync = TermsSync(memory, remote)

    /** Set when this build is older than the server's minimum (docs/MINIMUM-AGE-PLAN.md 4a): the social parts stay closed. */
    var updateRequired by mutableStateOf(false)

    /** Bumped on every change, so screens that read [hasAccepted] update. */
    private var changes by mutableIntStateOf(0)

    /** Whether the social parts are open: the person agreed to the current rules and this build is not too old. */
    fun hasAccepted(userId: String): Boolean {
        changes
        return !updateRequired && sync.hasAccepted(userId)
    }

    /** Agrees on this phone at once, and on the server as soon as it can be reached. */
    suspend fun accept(userId: String) {
        sync.accept(userId)
        changes++
        sync.sync(userId)
    }

    /** Takes over an agreement from another phone and sends one made here. Call it after signing in and at start. */
    suspend fun sync(userId: String) {
        if (sync.sync(userId)) changes++
    }
}
