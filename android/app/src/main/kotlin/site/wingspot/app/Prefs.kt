package site.wingspot.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import site.wingspot.core.DistanceUnit

/** Small settings and what the phone remembers about badges, per account. */
class Prefs(context: Context) {
    private val prefs = context.getSharedPreferences("prefs", Context.MODE_PRIVATE)

    /** How distances are shown. Compose reads it, so screens update when it changes. */
    var unit: DistanceUnit by mutableStateOf(DistanceUnit.entries.firstOrNull { it.name == prefs.getString("unit", null) } ?: DistanceUnit.KILOMETRES)
        private set

    fun chooseUnit(value: DistanceUnit) {
        unit = value
        prefs.edit().putString("unit", value.name).apply()
    }

    /** The highest level of each badge that was shown as a celebration. */
    fun acks(user: String): Map<String, Int> =
        prefs.all.filterKeys { it.startsWith("ack.$user.") }.mapKeys { it.key.removePrefix("ack.$user.") }.mapValues { (it.value as? Int) ?: 0 }

    fun setAcks(user: String, acks: Map<String, Int>) {
        val edit = prefs.edit()
        for ((badge, level) in acks) edit.putInt("ack.$user.$badge", maxOf(level, prefs.getInt("ack.$user.$badge", 0)))
        edit.apply()
    }

    /** When this account first appeared on this phone. Badges unlocked before then are not celebrated again. */
    fun firstSeen(user: String): Long {
        val key = "firstSeen.$user"
        val known = prefs.getLong(key, 0)
        if (known != 0L) return known
        val now = System.currentTimeMillis()
        prefs.edit().putLong(key, now).apply()
        return now
    }

    fun cachedProgress(user: String): String? = prefs.getString("progress.$user", null)

    fun cacheProgress(user: String, json: String) = prefs.edit().putString("progress.$user", json).apply()

    /** Forgets what this phone knows about the account, for example after it was deleted. */
    fun forget(user: String) {
        val edit = prefs.edit()
        for (key in prefs.all.keys) if (key.endsWith(".$user") || key.contains(".$user.")) edit.remove(key)
        edit.apply()
    }
}
