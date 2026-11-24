package site.wingspot.core

import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/** When a sighting or an airport check-in happened (#312): the moment to store, and whether its time of day is known. */
data class Moment(val at: Instant, val timeKnown: Boolean)

/**
 * What the "When" row has chosen: now, a day, or a day with a time. The same rules as iOS's `WhenChoice`.
 * A day without a time is stored at midday (so it stays on that day in any time zone) and marked as having no time.
 */
data class WhenChoice(val isNow: Boolean = true, val day: LocalDate? = null, val time: LocalTime? = null) {
    /** The moment to store. Today without a time is just now; a time later than now is cut back to now. */
    fun moment(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Moment {
        if (isNow) return Moment(now, true)
        val chosen = day ?: now.atZone(zone).toLocalDate()
        if (time != null) return Moment(minOf(chosen.atTime(time).atZone(zone).toInstant(), now), true)
        if (chosen == now.atZone(zone).toLocalDate()) return Moment(now, true)
        return Moment(chosen.atTime(12, 0).atZone(zone).toInstant(), false)
    }

    companion object {
        val NOW = WhenChoice()

        /** The choice an edit screen starts with: the check-in's own date, with its time when known. */
        fun existing(at: Instant, timeKnown: Boolean, zone: ZoneId = ZoneId.systemDefault()): WhenChoice {
            val local = at.atZone(zone)
            return WhenChoice(false, local.toLocalDate(), if (timeKnown) local.toLocalTime().withSecond(0).withNano(0) else null)
        }

        /** A suggestion from a photo's capture date: only when it is more than a day before now. */
        fun suggestion(takenAt: Instant?, now: Instant = Instant.now()): Instant? =
            takenAt?.takeIf { Duration.between(it, now) > Duration.ofHours(24) }

        /** The choice a tap on the suggestion sets: the photo's day and time. */
        fun usingPhoto(takenAt: Instant, zone: ZoneId = ZoneId.systemDefault()): WhenChoice = existing(takenAt, true, zone)
    }
}

/** Reads the capture date of a photo from its EXIF text. */
object PhotoDates {
    private val format = DateTimeFormatter.ofPattern("yyyy:MM:dd HH:mm:ss")
    private val oldest = Instant.parse("1990-01-01T00:00:00Z")

    /**
     * "2019:08:12 10:30:05" with an optional "+02:00" offset (else the phone's [zone]). Null when it is not a date, or from before 1990
     * (a camera with a reset clock).
     */
    fun parse(text: String?, offset: String? = null, zone: ZoneId = ZoneId.systemDefault()): Instant? {
        if (text == null) return null
        val local = try { LocalDateTime.parse(text.trim(), format) } catch (e: Exception) { return null }
        val where: ZoneId = offset?.trim()?.let { runCatching { ZoneOffset.of(it) }.getOrNull() } ?: zone
        return local.atZone(where).toInstant().takeIf { it >= oldest }
    }
}
