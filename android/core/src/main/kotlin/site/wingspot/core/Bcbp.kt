package site.wingspot.core

import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.math.abs

/**
 * Flight data read from an IATA Bar Coded Boarding Pass (Resolution 792), ported from the iPhone app's BCBP package.
 * The passenger name and booking reference are skipped while parsing and never exposed, so they can't be stored or
 * uploaded by accident.
 */
data class BoardingPass(val version: String?, val legs: List<Leg>) {
    data class Leg(
        val from: String,
        val to: String,
        val carrier: String,
        /** Without leading zeros, with an optional suffix: `400`, `32A`. */
        val flightNumber: String,
        /** Julian day of the flight (1 to 366). The year is not encoded, see [flightDate]. */
        val dayOfYear: Int,
        val compartmentCode: String,
        /** Without leading zeros: `34K`. Null when no seat is assigned. */
        val seat: String?,
    ) {
        /** The year that puts the date closest to [reference], usually the scan date. */
        fun flightDate(reference: LocalDate): LocalDate? =
            (reference.year - 1..reference.year + 1)
                .mapNotNull { year ->
                    val start = LocalDate.of(year, 1, 1)
                    if (dayOfYear <= start.lengthOfYear()) start.plusDays(dayOfYear - 1L) else null
                }
                .minByOrNull { abs(ChronoUnit.DAYS.between(reference, it)) }
    }

    companion object {
        /** Parses the text of a BCBP barcode (PDF417, Aztec or QR). Throws [BcbpException]. */
        fun parse(barcode: String): BoardingPass {
            val scanner = FieldScanner(barcode)
            if (scanner.take(1) != "M") throw BcbpException("invalidFormatCode")
            val legCount = scanner.take(1).toIntOrNull()?.takeIf { it in 1..4 } ?: throw BcbpException("invalidLegCount")
            scanner.skip(20) // passenger name
            scanner.skip(1) // electronic ticket indicator

            val legs = mutableListOf<Leg>()
            var version: String? = null
            for (index in 0 until legCount) {
                scanner.skip(7) // booking reference
                val from = scanner.airportCode("from")
                val to = scanner.airportCode("to")
                val carrier = scanner.take(3).trim()
                val flightNumber = scanner.take(5).trim().droppingLeadingZeros()
                val dayOfYear = scanner.take(3).toIntOrNull()?.takeIf { it in 1..366 } ?: throw BcbpException("invalidField")
                val compartment = scanner.take(1).trim()
                val seat = scanner.take(4).trim().droppingLeadingZeros()
                scanner.skip(5) // check-in sequence number
                scanner.skip(1) // passenger status
                val size = scanner.take(2).toIntOrNull(16) ?: throw BcbpException("invalidField")
                val conditional = scanner.take(size)

                if (index == 0 && conditional.firstOrNull() == '>' && conditional.length >= 2) version = conditional.substring(1, 2)
                if (carrier.isEmpty() || flightNumber.isEmpty()) throw BcbpException("invalidField")
                legs += Leg(from, to, carrier, flightNumber, dayOfYear, compartment, seat.ifEmpty { null })
            }
            // Anything after the legs (security data, airline use) is ignored.
            return BoardingPass(version, legs)
        }
    }
}

/** [code] is one of the stable identifiers shared with the iPhone app in `contracts/test-vectors/bcbp.json`. */
class BcbpException(val code: String) : Exception(code)

private class FieldScanner(private var rest: String) {
    fun take(length: Int): String {
        if (rest.length < length) throw BcbpException("truncated")
        return rest.take(length).also { rest = rest.drop(length) }
    }

    fun skip(length: Int) {
        take(length)
    }

    fun airportCode(@Suppress("UNUSED_PARAMETER") field: String): String {
        val code = take(3)
        if (!code.all { it in 'A'..'Z' || it in 'a'..'z' }) throw BcbpException("invalidField")
        return code
    }
}

/** `0400` is `400`, `0032A` is `32A`, `034K` is `34K`, `0000` is `0`. */
private fun String.droppingLeadingZeros(): String {
    if (firstOrNull() != '0') return this
    val stripped = dropWhile { it == '0' }
    return if (stripped.firstOrNull()?.isDigit() == true) stripped else "0$stripped"
}
