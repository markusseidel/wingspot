package site.wingspot.core

import java.io.File
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** The same vector files the iPhone app is tested with, from `contracts/test-vectors`. */
private fun vectors(name: String): JsonObject {
    // Gradle runs tests with the module directory (android/core) as the working directory.
    val file = File("../../contracts/test-vectors/$name.json")
    return Json.parseToJsonElement(file.readText()).jsonObject
}

private fun JsonElement.text() = if (this is JsonNull) null else jsonPrimitive.content

class VectorTests {
    @Test
    fun boardingPasses() {
        val cases = vectors("bcbp")["cases"]!!.jsonArray
        assert(cases.size >= 15) { "expected the shared vectors, found ${cases.size}" }
        for (case in cases) {
            val c = case.jsonObject
            val name = c["name"]!!.text()
            val barcode = c["barcode"]!!.text()!!
            val expectedError = c["expectedError"]?.text()
            if (expectedError != null) {
                val error = runCatching { BoardingPass.parse(barcode) }.exceptionOrNull()
                assert(error is BcbpException) { "$name: expected an error, got $error" }
                assertEquals(expectedError, (error as BcbpException).code, name)
                continue
            }
            val expected = c["expected"]!!.jsonObject
            val pass = BoardingPass.parse(barcode)
            assertEquals(expected["version"]!!.text(), pass.version, name)
            val legs = expected["legs"]!!.jsonArray
            assertEquals(legs.size, pass.legs.size, name)
            val reference = LocalDate.parse(c["referenceDate"]!!.text()!!)
            for ((leg, wanted) in pass.legs.zip(legs)) {
                val w = wanted.jsonObject
                assertEquals(w["from"]!!.text(), leg.from, name)
                assertEquals(w["to"]!!.text(), leg.to, name)
                assertEquals(w["carrier"]!!.text(), leg.carrier, name)
                assertEquals(w["flightNumber"]!!.text(), leg.flightNumber, name)
                assertEquals(w["dayOfYear"]!!.jsonPrimitive.int, leg.dayOfYear, name)
                assertEquals(w["compartmentCode"]!!.text(), leg.compartmentCode, name)
                assertEquals(w["seat"]?.text(), leg.seat, name)
                assertEquals(LocalDate.parse(w["flightDate"]!!.text()!!), leg.flightDate(reference), name)
            }
        }
    }

    @Test
    fun theBoardingPassDoesNotExposePassengerData() {
        val first = vectors("bcbp")["cases"]!!.jsonArray[0].jsonObject["barcode"]!!.text()!!
        val dump = BoardingPass.parse(first).toString()
        assertFalse("DOE" in dump)
        assertFalse("ABC123" in dump)
    }

    @Test
    fun registrations() {
        val cases = vectors("registrations")["cases"]!!.jsonArray
        assert(cases.size >= 40)
        for (case in cases) {
            val c = case.jsonObject
            val input = c["input"]!!.text()!!
            val expected = c["expected"]!!.text()
            val parsed = Registration.parse(input)
            assertEquals(expected, parsed?.value, "input '$input'")
            if (expected != null) assertEquals(c["country"]!!.text(), parsed!!.countryCode, "country of '$input'")
            else assertNull(parsed)
        }
    }

    @Test
    fun distances() {
        val file = vectors("distances")
        val tolerance = file["toleranceKm"]!!.jsonPrimitive.double
        for (case in file["cases"]!!.jsonArray) {
            val c = case.jsonObject
            fun point(key: String) = c[key]!!.jsonObject.let {
                GeoCoordinate(it["latitude"]!!.jsonPrimitive.double, it["longitude"]!!.jsonPrimitive.double)
            }
            val from = point("from")
            val to = point("to")
            val label = "${c["from"]!!.jsonObject["code"]!!.text()} to ${c["to"]!!.jsonObject["code"]!!.text()}"
            val expectedKm = c["expectedKm"]!!.jsonPrimitive.double
            val actual = GreatCircle.distanceKm(from, to)
            assert(kotlin.math.abs(actual - expectedKm) <= tolerance) { "$label: $actual vs $expectedKm" }
            assertEquals(c["crossesEquator"]!!.jsonPrimitive.content.toBoolean(), GreatCircle.crossesEquator(from, to), label)
            assertEquals(c["crossesAntimeridian"]!!.jsonPrimitive.content.toBoolean(), GreatCircle.crossesAntimeridian(from, to), label)
        }
        assertNotNull(file["cases"])
    }
}
