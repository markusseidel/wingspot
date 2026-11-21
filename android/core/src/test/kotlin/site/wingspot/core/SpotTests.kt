package site.wingspot.core

import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SpotTests {
    @Test
    fun aGoogleMapsLinkGivesThePlaceNotTheView() {
        val link = "https://www.google.com/maps/place/Terminal+2/@50.0452,8.5705,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d50.0461!4d8.5712"
        assertEquals(50.0461 to 8.5712, MapsLink.coordinate(link))
    }

    @Test
    fun otherCommonLinksAreRead() {
        assertEquals(50.04, MapsLink.coordinate("https://www.google.com/maps/@50.04,8.57,15z")!!.first)
        assertEquals(8.6, MapsLink.coordinate("https://maps.apple.com/?ll=50.1,8.6&q=Deck")!!.second)
        assertEquals(8.7, MapsLink.coordinate("https://www.google.com/maps/search/?api=1&query=50.2%2C8.7")!!.second)
        assertEquals(-8.5, MapsLink.coordinate("50.05, -8.5")!!.second)
    }

    @Test
    fun textWithoutAPositionOrWithAnImpossibleOneIsRefused() {
        assertNull(MapsLink.coordinate("https://maps.app.goo.gl/abc123"))
        assertNull(MapsLink.coordinate("hello"))
        assertNull(MapsLink.coordinate("95.0, 8.5"))
        assertNull(MapsLink.coordinate("50.0, 190.5"))
    }

    @Test
    fun aSessionRoundTripsAndRunsOutAfterTwelveHours() {
        val start = Instant.parse("2026-11-01T10:00:00Z")
        val session = SpotSession(UUID.randomUUID(), 42, "Terminal 2 deck", 7, "FRA", start)
        assertEquals(session, SpotSession.decode(session.encode()))
        assertTrue(session.isActive(start.plusSeconds(11 * 3600)))
        assertFalse(session.isActive(start.plusSeconds(12 * 3600)))
        assertNull(SpotSession.decode(null))
        assertNull(SpotSession.decode("{broken"))
    }
}
