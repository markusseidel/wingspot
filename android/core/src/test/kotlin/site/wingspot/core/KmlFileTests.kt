package site.wingspot.core

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class KmlFileTests {
    @Test
    fun aKmlFileIsRecognisedByItsTypeOrItsName() {
        assertTrue(KmlFile.looksLikeKml("application/vnd.google-earth.kml+xml", null))
        assertTrue(KmlFile.looksLikeKml("APPLICATION/VND.GOOGLE-EARTH.KML+XML", "x"))
        assertTrue(KmlFile.looksLikeKml("application/octet-stream", "LH400.kml"))
        assertTrue(KmlFile.looksLikeKml(null, "LH400.KML"))
    }

    @Test
    fun otherFilesAreNot() {
        assertFalse(KmlFile.looksLikeKml("application/vnd.google-earth.kmz", "track.kmz"))
        assertFalse(KmlFile.looksLikeKml("application/gpx+xml", "track.gpx"))
        assertFalse(KmlFile.looksLikeKml(null, "kml"))
        assertFalse(KmlFile.looksLikeKml(null, null))
    }
}
