package site.wingspot.app

import android.content.Context

/** Whether this person has accepted the community rules, kept on the phone per account. Raise [CURRENT_VERSION] when the rules change. */
class TermsStore(context: Context) {
    private val prefs = context.getSharedPreferences("terms", Context.MODE_PRIVATE)

    fun hasAccepted(userId: String): Boolean = prefs.getInt(userId, 0) >= CURRENT_VERSION

    fun accept(userId: String) = prefs.edit().putInt(userId, CURRENT_VERSION).apply()

    companion object {
        const val CURRENT_VERSION = 1
    }
}
