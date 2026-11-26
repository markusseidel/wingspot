package site.wingspot.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import site.wingspot.core.DistanceUnit
import site.wingspot.core.FeedSort

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

    /** How the lists of check-ins in the collections are sorted: by which date, and in which direction. Compose reads them. */
    var collectionDate: site.wingspot.core.CollectionDateKind by mutableStateOf(
        site.wingspot.core.CollectionDateKind.entries.firstOrNull { it.name == prefs.getString("collectionDate", null) } ?: site.wingspot.core.CollectionDateKind.FLIGHT,
    )
        private set
    var collectionAscending: Boolean by mutableStateOf(prefs.getBoolean("collectionAscending", false))
        private set

    fun chooseCollectionSort(date: site.wingspot.core.CollectionDateKind, ascending: Boolean) {
        collectionDate = date
        collectionAscending = ascending
        prefs.edit().putString("collectionDate", date.name).putBoolean("collectionAscending", ascending).apply()
    }

    /** False when the server switched the KML import off. On until the server says otherwise. Compose reads it. */
    var kmlImportOn: Boolean by mutableStateOf(prefs.getBoolean("kmlImportOn", true))
        private set

    fun rememberKmlImport(value: Boolean) {
        kmlImportOn = value
        prefs.edit().putBoolean("kmlImportOn", value).apply()
    }

    /** The last minimum Android version the server sent (docs/MINIMUM-AGE-PLAN.md 4a), null when none is known. */
    val minimumVersion: String? get() = prefs.getString("minimumAppVersion", null)

    fun rememberMinimumVersion(value: String?) {
        prefs.edit().putString("minimumAppVersion", value).apply()
    }

    /** How the Feed tab is sorted. */
    var feedSort: FeedSort = FeedSort.entries.firstOrNull { it.name == prefs.getString("feedSort", null) } ?: FeedSort.CREATED
        private set

    fun chooseFeedSort(value: FeedSort) {
        feedSort = value
        prefs.edit().putString("feedSort", value.name).apply()
    }

    /** True once the person chose to show airports near them. */
    var usesLocation: Boolean by mutableStateOf(prefs.getBoolean("usesLocation", false))
        private set

    fun chooseLocation(value: Boolean) {
        usesLocation = value
        prefs.edit().putBoolean("usesLocation", value).apply()
    }

    /** The running spotting session, as [site.wingspot.core.SpotSession.encode] wrote it. */
    var spotSession: String?
        get() = prefs.getString("spotSession", null)
        set(value) { prefs.edit().apply { if (value == null) remove("spotSession") else putString("spotSession", value) }.apply() }

    /** True once the phone was asked for permission to show notifications, so it is asked once and not at every start. */
    var askedForNotifications: Boolean
        get() = prefs.getBoolean("askedForNotifications", false)
        set(value) { prefs.edit().putBoolean("askedForNotifications", value).apply() }

    /** This phone's id on the server, made once. */
    fun deviceId(): String = prefs.getString("deviceId", null) ?: java.util.UUID.randomUUID().toString().also { prefs.edit().putString("deviceId", it).apply() }

    /** The highest level of each badge that was shown as a celebration. */
    fun acks(user: String): Map<String, Int> =
        prefs.all.filterKeys { it.startsWith("ack.$user.") }.mapKeys { it.key.removePrefix("ack.$user.") }.mapValues { (it.value as? Int) ?: 0 }

    fun setAcks(user: String, acks: Map<String, Int>) {
        val edit = prefs.edit()
        for ((badge, level) in acks) edit.putInt("ack.$user.$badge", maxOf(level, prefs.getInt("ack.$user.$badge", 0)))
        edit.apply()
    }

    /** Takes back what was shown for badges that went down, so earning them again is celebrated again. */
    fun lowerAcks(user: String, acks: Map<String, Int>) {
        if (acks.isEmpty()) return
        val edit = prefs.edit()
        for ((badge, level) in acks) edit.putInt("ack.$user.$badge", level)
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

    /** The release notes the server sent last time, as JSON, so the screen opens offline. */
    var releaseNotesCache: String?
        get() = prefs.getString("releaseNotes", null)
        set(value) = prefs.edit().putString("releaseNotes", value).apply()

    /** The announcements the server sent last time, as JSON, so the card shows offline. */
    var announcementsCache: String?
        get() = prefs.getString("announcements", null)
        set(value) = prefs.edit().putString("announcements", value).apply()

    /** The ids of the announcements this person dismissed on this phone. */
    var dismissedAnnouncements: Set<String>
        get() = prefs.getStringSet("announcementsDismissed", emptySet()).orEmpty().toSet()
        set(value) = prefs.edit().putStringSet("announcementsDismissed", value).apply()

    /** Forgets what this phone knows about the account, for example after it was deleted. */
    fun forget(user: String) {
        val edit = prefs.edit()
        for (key in prefs.all.keys) if (key.endsWith(".$user") || key.contains(".$user.")) edit.remove(key)
        edit.apply()
    }
}
