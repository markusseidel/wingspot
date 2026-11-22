package site.wingspot.core

import java.io.File
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** The made-up tracks the iPhone app is tested with, from `contracts/test-vectors/tracks.json`. */
class FlightTrackTests {
    private val file = Json.parseToJsonElement(File("../../contracts/test-vectors/tracks.json").readText()).jsonObject
    private val toleranceKm = file["toleranceKm"]!!.jsonPrimitive.double
    private val toleranceDegrees = file["toleranceDegrees"]!!.jsonPrimitive.double
    private val cases = file["cases"]!!.jsonArray.map { it.jsonObject }

    private fun JsonObject.name() = get("name")!!.jsonPrimitive.content
    private fun JsonObject.points() = get("points")!!.jsonArray.map { GeoCoordinate(it.jsonArray[1].jsonPrimitive.double, it.jsonArray[0].jsonPrimitive.double) }
    private fun JsonObject.doubles(key: String) = get(key)!!.jsonArray.map { it.jsonPrimitive.double }
    private fun case(name: String) = cases.first { it.name() == name }

    @Test
    fun theVectorsAreThere() = assertTrue(cases.size >= 9)

    @Test
    fun lengthMatchesVector() {
        for (case in cases) {
            assertTrue(abs(FlightTrack.lengthKm(case.points()) - case["lengthKm"]!!.jsonPrimitive.double) <= toleranceKm, case.name())
            assertEquals(case["crossesAntimeridian"]!!.jsonPrimitive.boolean, FlightTrack.crossesAntimeridian(case.points()), case.name())
        }
    }

    @Test
    fun unwrappingMatchesVectorAndNeverJumps() {
        for (case in cases) {
            val result = FlightTrack.unwrapped(case.points())
            val expected = case.doubles("unwrappedLongitudes")
            assertEquals(expected.size, result.size, case.name())
            for ((value, wanted) in result.zip(expected)) assertTrue(abs(value.longitude - wanted) <= toleranceDegrees, case.name())
            for ((a, b) in result.zipWithNext()) assertTrue(abs(b.longitude - a.longitude) <= 180, case.name())
            assertTrue(abs(FlightTrack.lengthKm(result) - case["lengthKm"]!!.jsonPrimitive.double) <= toleranceKm, case.name())
        }
    }

    @Test
    fun simplifyingMatchesVector() {
        for (case in cases) {
            val result = FlightTrack.simplified(case.points(), case["toleranceMeters"]!!.jsonPrimitive.double)
            assertEquals(case["simplifiedCount"]!!.jsonPrimitive.int, result.size, case.name())
            val longitudes = case.doubles("simplifiedLongitudes")
            val latitudes = case.doubles("simplifiedLatitudes")
            for ((index, value) in result.withIndex()) {
                assertTrue(abs(value.longitude - longitudes[index]) <= toleranceDegrees, case.name())
                assertTrue(abs(value.latitude - latitudes[index]) <= toleranceDegrees, case.name())
            }
        }
    }

    @Test
    fun aLighterTrackIsAboutAsLong() {
        val c = case("Tokyo to Los Angeles, made up, across the date line")
        val light = FlightTrack.simplified(c.points(), 5_000.0)
        assertTrue(light.size <= c.points().size)
        val full = c["lengthKm"]!!.jsonPrimitive.double
        assertTrue(abs(FlightTrack.lengthKm(light) - full) / full < 0.01)
    }

    @Test
    fun theBoxCoversTheUnwrappedTrack() {
        val box = assertNotNull(FlightTrack.boundingBox(case("Tokyo to Los Angeles, made up, across the date line").points()))
        assertEquals(139.78, box.minLongitude)
        assertTrue(abs(box.maxLongitude - 241.59) < 0.00001)
        assertEquals(33.94, box.minLatitude)
        assertEquals(46.0, box.maxLatitude)
        assertNull(FlightTrack.boundingBox(emptyList()))
    }

    @Test
    fun aDetourIsTheDifferenceAndItsPercentage() {
        val detour = assertNotNull(FlightTrack.detour(11_000.0, 9_000.0))
        assertEquals(2_000.0, detour.extraKm)
        assertTrue(abs(detour.percent - 22.2222) < 0.001)
        assertNull(FlightTrack.detour(100.0, 0.0))
    }

    @Test
    fun fewerThanTwoPointsHaveNoLength() {
        assertEquals(0.0, FlightTrack.lengthKm(emptyList()))
        assertEquals(0.0, FlightTrack.lengthKm(listOf(GeoCoordinate(1.0, 1.0))))
        assertTrue(FlightTrack.unwrapped(emptyList()).isEmpty())
        assertTrue(FlightTrack.simplified(emptyList(), 100.0).isEmpty())
    }
}

class FlownRouteTests {
    private fun equator(vararg longitudes: Int) = longitudes.map { GeoCoordinate(0.0, it.toDouble()) }

    @Test
    fun aFlownRouteIsSummarisedForTheFlightPage() {
        // A made-up route that goes from 0° to 10° east on the equator, then back 5° to the west: 15° of arc.
        val route = FlightTrack.flownRoute(equator(*(0..10).toList().toIntArray()) + equator(*(9 downTo 5).toList().toIntArray()), 556)
        assertEquals(FlownRoute(1668, 1112, 200), route)
    }

    @Test
    fun aRouteWithoutAClearDetourHasNoExtra() {
        val straight = equator(*(0..10).toList().toIntArray())
        assertEquals(FlownRoute(1112, 0, 0), FlightTrack.flownRoute(straight, 1112))
        assertEquals(FlownRoute(1112, 0, 0), FlightTrack.flownRoute(straight, 1500), "shorter than the airport figure is not a detour")
        assertEquals(1112, FlightTrack.flownRoute(straight, null)?.flownKm)
    }

    @Test
    fun tooFewPositionsAreNoRoute() {
        assertEquals(null, FlightTrack.flownRoute(emptyList(), 100))
        assertEquals(null, FlightTrack.flownRoute(equator(1), 100))
    }
}

class FlownRouteStatsTests {
    @Test
    fun summarisesTheFlightsWithARoute() {
        val stats = FlownRouteStats.of(listOf(2102.0 to 2004.0, 504.4 to 500.0, 11_486.0 to 9_900.0))
        assertEquals(FlownRouteStats(3, 14_092, 11_486, 1_586), stats)
    }

    @Test
    fun noClearDetourOrNoAirportsMeansNoDetour() {
        assertEquals(0, FlownRouteStats.of(listOf(100.0 to 120.0))?.biggestDetourKm)
        assertEquals(0, FlownRouteStats.of(listOf(100.0 to null))?.biggestDetourKm)
        assertEquals(null, FlownRouteStats.of(emptyList()))
    }
}
