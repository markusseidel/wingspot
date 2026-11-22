package site.wingspot.core

import java.time.Instant
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals

class FeedDateRuleTests {
    private val utc = ZoneId.of("UTC")
    private val now = Instant.parse("2026-11-22T12:00:00Z")
    private fun style(then: String) = FeedDateRule.style(Instant.parse(then), now, utc)

    @Test
    fun recentTimesAreRelative() {
        assertEquals(FeedDateStyle.RELATIVE, style("2026-11-22T11:55:00Z"))
        assertEquals(FeedDateStyle.RELATIVE, style("2026-11-19T12:01:00Z"))
        assertEquals(FeedDateStyle.RELATIVE, style("2026-11-22T13:00:00Z"), "a time just ahead is still relative")
    }

    @Test
    fun afterAWeekItIsADateWithoutTheCurrentYear() {
        assertEquals(FeedDateStyle.DATE, style("2026-11-13T12:00:00Z"))
        assertEquals(FeedDateStyle.DATE, style("2026-01-02T12:00:00Z"))
    }

    @Test
    fun anEarlierYearShowsTheYear() {
        assertEquals(FeedDateStyle.DATE_WITH_YEAR, style("2025-06-29T12:00:00Z"), "the old rule would say last year")
        assertEquals(FeedDateStyle.DATE_WITH_YEAR, style("2013-09-15T12:00:00Z"))
    }

    @Test
    fun theWeekBoundaryIsExactly7Days() {
        assertEquals(FeedDateStyle.DATE, style("2026-11-15T12:00:00Z"))
        assertEquals(FeedDateStyle.RELATIVE, style("2026-11-15T12:00:01Z"))
    }
}
