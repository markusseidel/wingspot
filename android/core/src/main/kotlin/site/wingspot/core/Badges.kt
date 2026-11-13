package site.wingspot.core

import java.time.OffsetDateTime
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Text by language code, such as `{"en": "Wheels Up", "de": "Abheben"}`. English is always there. */
@Serializable
data class LocalizedText(val values: Map<String, String> = emptyMap()) {
    /** The first of [languages] that has a text, then English, then whatever there is. */
    fun resolved(languages: List<String>): String {
        for (language in languages) values[language.substringBefore('-').substringBefore('_')]?.let { return it }
        return values["en"] ?: values.values.sorted().firstOrNull().orEmpty()
    }
}

@Serializable
data class BadgeProgress(
    val id: String,
    val name: Map<String, String> = emptyMap(),
    val description: Map<String, String>? = null,
    val category: String = "",
    @SerialName("hidden") val isHidden: Boolean = false,
    /** The value needed for each level, ascending. One entry for a single badge. */
    val levels: List<Int>,
    /** The current value of the badge's metric. */
    val value: Int,
    /** The highest level unlocked, 0 if none. It never goes down. */
    val level: Int,
    @SerialName("unlocked_at") val unlockedAt: String? = null,
) {
    val isSingle: Boolean get() = levels.size <= 1
    val isComplete: Boolean get() = level >= levels.size
    /** The value for the next level, or null once every level is unlocked. */
    val nextTarget: Int? get() = levels.getOrNull(level)
    fun title(languages: List<String>) = LocalizedText(name).resolved(languages)
    fun text(languages: List<String>) = description?.let { LocalizedText(it).resolved(languages) }
    fun unlockedInstant() = unlockedAt?.let { runCatching { OffsetDateTime.parse(it).toInstant() }.getOrNull() }
}

@Serializable
data class UserProgress(
    val xp: Int,
    val level: Int,
    /** The XP at which the current level starts. */
    @SerialName("xp_for_level") val xpForLevel: Int,
    @SerialName("xp_for_next_level") val xpForNextLevel: Int,
    val badges: List<BadgeProgress> = emptyList(),
    /** How many hidden badges are still locked. */
    @SerialName("hidden_remaining") val hiddenRemaining: Int = 0,
) {
    /** 0 at the start of the level, 1 when the next level is reached. */
    val levelFraction: Float
        get() {
            val span = xpForNextLevel - xpForLevel
            return if (span > 0) ((xp - xpForLevel).toFloat() / span).coerceIn(0f, 1f) else 0f
        }
    val earnedCount: Int get() = badges.count { it.level > 0 }
}

enum class Rank(val firstLevel: Int) {
    CADET(0), STUDENT_PILOT(5), FIRST_OFFICER(10), CAPTAIN(15), SENIOR_CAPTAIN(20), CHIEF_PILOT(25), ACE(30), LEGEND(35);

    companion object {
        fun of(level: Int) = entries.last { level >= it.firstLevel }
    }
}

enum class BadgeFilter {
    ALL, EARNED,
    /** Not every level reached yet, so there is something left to work on. */
    IN_PROGRESS;

    fun matches(badge: BadgeProgress) = when (this) {
        ALL -> true
        EARNED -> badge.level > 0
        IN_PROGRESS -> !badge.isComplete
    }
}

/** A badge level to celebrate. [previousLevel] is what was shown before, 0 for a new badge. */
data class Celebration(val badge: BadgeProgress, val previousLevel: Int) {
    val id: String get() = "${badge.id}#${badge.level}"
}

object Celebrations {
    /** Unlocks within this long before the account appeared still count as new, so a slightly wrong clock can't swallow the first one. */
    private const val CLOCK_MARGIN_MS = 5 * 60 * 1000L

    /**
     * The server decides what is unlocked. This celebrates the difference between that and what was already shown, so a
     * lost answer or an unlock on another device never loses a celebration. Badges unlocked before the account first
     * appeared on this phone are not celebrated: they go into [newAcks] only.
     */
    fun compute(progress: UserProgress, acks: Map<String, Int>, firstSeenAtMs: Long): Result {
        val cutoff = firstSeenAtMs - CLOCK_MARGIN_MS
        val pending = mutableListOf<Celebration>()
        val silent = mutableMapOf<String, Int>()
        for (badge in progress.badges) {
            if (badge.level <= 0) continue
            val seen = acks[badge.id] ?: 0
            if (badge.level <= seen) continue
            val unlocked = badge.unlockedInstant()?.toEpochMilli()
            if (unlocked != null && unlocked >= cutoff) pending += Celebration(badge, seen) else silent[badge.id] = badge.level
        }
        return Result(pending, silent)
    }

    data class Result(val celebrations: List<Celebration>, val newAcks: Map<String, Int>)
}
