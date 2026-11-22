package site.wingspot.core

import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import kotlin.math.abs

/** How the date on a feed entry is written (docs/FEED-ENTRY-SPEC.md). The same rule as iOS's `FeedDate`. */
enum class FeedDateStyle { RELATIVE, DATE, DATE_WITH_YEAR }

object FeedDateRule {
    /**
     * Relative for the last 7 days ("3 hours ago"); after that a short date, with the year only when it is not the
     * current year, so a backdated flight shows its real date.
     */
    fun style(then: Instant, now: Instant, zone: ZoneId = ZoneId.systemDefault()): FeedDateStyle = when {
        abs(Duration.between(then, now).toMillis()) < 7 * 24 * 3600 * 1000L -> FeedDateStyle.RELATIVE
        then.atZone(zone).year == now.atZone(zone).year -> FeedDateStyle.DATE
        else -> FeedDateStyle.DATE_WITH_YEAR
    }
}
