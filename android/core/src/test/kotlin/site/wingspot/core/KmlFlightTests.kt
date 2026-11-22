package site.wingspot.core

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** The made-up KML files the iPhone app is tested with, from `contracts/test-vectors/kml`. */
class KmlFlightTests {
    private val cases = Json.parseToJsonElement(File("../../contracts/test-vectors/kml-flights.json").readText())
        .jsonObject["cases"]!!.jsonArray.map { it.jsonObject }

    private fun text(file: String) = File("../../contracts/test-vectors/kml/$file").readText()
    private fun JsonObject.str(key: String): String? = get(key)?.let { if (it is JsonNull) null else it.jsonPrimitive.content }
    private fun airport(element: JsonElement?): KmlAirport? = (element as? JsonObject)?.let {
        KmlAirport(iata = it.str("iata"), icao = it.str("icao"), name = it.str("name"), city = it.str("city"))
    }

    @Test
    fun readsEveryFile() {
        assertTrue(cases.size >= 6)
        for (case in cases) {
            val file = case.str("file")!!
            if (case.str("error") != null) {
                assertFailsWith<KmlFlightException>(file) { KmlFlightParser.parse(text(file)) }
                continue
            }
            val flight = KmlFlightParser.parse(text(file))
            assertEquals(case.str("title"), flight.title, file)
            assertEquals(case.str("flightNumber"), flight.flightNumber, file)
            assertEquals(case.str("airline"), flight.airline, file)
            assertEquals(airport(case["origin"]), flight.origin, "$file origin")
            assertEquals(airport(case["destination"]), flight.destination, "$file destination")
            assertEquals(case.str("departureDate"), flight.departureDate, file)
            assertEquals(case.str("departureTime"), flight.departureTime, file)
            assertEquals(case.str("arrivalTime"), flight.arrivalTime, file)
            assertEquals(case.str("aircraftTypeCode"), flight.aircraftTypeCode, file)
            assertEquals(case.str("aircraftTypeName"), flight.aircraftTypeName, file)
            assertEquals(case.str("registration"), flight.registration, file)
            assertEquals(case.str("flightLink"), flight.flightLink, file)
            assertEquals(case.str("trackSource"), flight.trackSource.code, file)
            assertEquals(case["trackPoints"]!!.jsonPrimitive.int, flight.track.size, file)
            val first = case["trackFirst"]?.jsonArray
            val last = case["trackLast"]?.jsonArray
            if (first != null && last != null) {
                assertEquals(GeoCoordinate(first[1].jsonPrimitive.double, first[0].jsonPrimitive.double), flight.track.first(), file)
                assertEquals(GeoCoordinate(last[1].jsonPrimitive.double, last[0].jsonPrimitive.double), flight.track.last(), file)
            }
        }
    }

    @Test
    fun theDateLineTrackKeepsItsRawLongitudes() {
        val flight = KmlFlightParser.parse(text("date-line.kml"))
        assertTrue(FlightTrack.crossesAntimeridian(flight.track))
        assertTrue(flight.track.any { it.longitude >= 179 } && flight.track.any { it.longitude < -170 })
    }

    @Test
    fun aMissingFieldNeverStopsTheImport() {
        val flight = KmlFlightParser.parse("<kml><Document><Placemark><description>nothing useful</description></Placemark></Document></kml>")
        assertNull(flight.flightNumber)
        assertNull(flight.origin)
        assertTrue(flight.track.isEmpty())
        assertEquals(KmlTrackSource.NONE, flight.trackSource)
    }

    @Test
    fun positionsOutsideTheEarthAreSkipped() {
        val points = KmlFlightParser.parseCoordinates("10,20,0 200,20,0 10,95,0 bad 11,21 12,22,500\n13,23")
        assertEquals(listOf(10.0, 11.0, 12.0, 13.0), points.map { it.longitude })
    }

    @Test
    fun aDescriptionInAnEntityEscapedFormAndInCdataReadTheSame() {
        val escaped = "<kml><Document><Placemark><description>From: &lt;b&gt;Test Airport (ABC)&lt;/b&gt;</description></Placemark></Document></kml>"
        val cdata = "<kml><Document><Placemark><description><![CDATA[From: <b>Test Airport (ABC)</b>]]></description></Placemark></Document></kml>"
        assertEquals(KmlFlightParser.parse(escaped).origin, KmlFlightParser.parse(cdata).origin)
        assertEquals(KmlAirport(iata = "ABC", name = "Test Airport"), KmlFlightParser.parse(cdata).origin)
    }

    @Test
    fun aLongTrackOfFiftyThousandPositionsIsRead() {
        val line = (0 until 50_000).joinToString(" ") { "${it * 0.0001 - 10},${45 + (it % 100) * 0.0001},9000" }
        val flight = KmlFlightParser.parse("<kml><Document><Placemark><LineString><coordinates>$line</coordinates></LineString></Placemark></Document></kml>")
        assertEquals(50_000, flight.track.size)
    }

    @Test
    fun aLinkWithAnIdIsNotAFlightNumber() {
        val kml = "<kml><Document><Placemark><description>&lt;a href=\"https://www.flightradar24.com/flight/3f2a1b9c4d\"&gt;x&lt;/a&gt;</description></Placemark></Document></kml>"
        val flight = KmlFlightParser.parse(kml)
        assertNull(flight.flightNumber)
        assertEquals("https://www.flightradar24.com/flight/3f2a1b9c4d", flight.flightLink)
    }

    @Test
    fun theDepartureDayIsNeverInTheFuture() {
        val today = java.time.LocalDate.of(2026, 11, 22)
        assertNull(KmlFlight().departureDay(today))
        assertEquals(java.time.LocalDate.of(2026, 11, 2), KmlFlight(departureDate = "2026-11-02").departureDay(today))
        assertEquals(today, KmlFlight(departureDate = "2027-01-05").departureDay(today))
        assertNull(KmlFlight(departureDate = "not a date").departureDay(today))
    }
}
