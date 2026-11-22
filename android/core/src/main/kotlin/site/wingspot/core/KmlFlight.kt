package site.wingspot.core

/** An airport as a KML file names it. Every part is optional. */
data class KmlAirport(val iata: String? = null, val icao: String? = null, val name: String? = null, val city: String? = null) {
    val isEmpty: Boolean get() = iata == null && icao == null && name == null && city == null
}

/** Where the track of a flight was found. */
enum class KmlTrackSource(val code: String) {
    /** The longest line of positions in the file. */
    LINE("line"),
    /** The single position reports, sorted by their time stamp. */
    PLACEMARKS("placemarks"),
    /** No usable track. */
    NONE("none"),
}

/**
 * What a KML file of one flight says. **Every field is optional.** A field that was not found stays empty and never stops
 * the import. Times are kept as the text the file has, because the time zone of the times in the description is not yet
 * confirmed, and the person checks them on the review screen anyway.
 */
data class KmlFlight(
    val title: String? = null,
    val flightNumber: String? = null,
    val airline: String? = null,
    val origin: KmlAirport? = null,
    val destination: KmlAirport? = null,
    /** `yyyy-MM-dd`, from the description or else from the first time stamp (UTC). */
    val departureDate: String? = null,
    /** `HH:mm` as written in the file. */
    val departureTime: String? = null,
    val arrivalTime: String? = null,
    val aircraftTypeCode: String? = null,
    val aircraftTypeName: String? = null,
    val registration: String? = null,
    /** The link to the flight in the file, as written. It tells two imports of the same flight apart. */
    val flightLink: String? = null,
    /** The positions in the order they were flown, as in the file. */
    val track: List<GeoCoordinate> = emptyList(),
    val trackSource: KmlTrackSource = KmlTrackSource.NONE,
)

/** The text is not a KML file. */
class KmlFlightException : Exception("not a KML file")

/**
 * Reads a KML file of one flight, as exported by flight-tracking sites. The text inside `<description>` is HTML that no one
 * documents and that has already changed, so everything is looked up leniently and nothing is required. Two layouts are
 * known (a newer one with airport links and an older one with "From:" and "To:" lines). The same code runs on iOS and is
 * checked against the made-up files in `contracts/test-vectors/kml`.
 */
object KmlFlightParser {
    /** A block of positions with fewer points than this is the straight line from the origin to the destination, not a track. */
    private const val MINIMUM_LINE_POINTS = 3

    fun parse(text: String): KmlFlight {
        if (!(text.contains("<kml") || text.contains("<Document") || text.contains("<coordinates"))) throw KmlFlightException()
        var flight = KmlFlight(title = elements("name", text).firstOrNull()?.let(::clean)?.takeIf { it.isNotEmpty() })
        val descriptions = elements("description", text).map(::descriptionHtml)

        val (track, source) = findTrack(text)
        flight = flight.copy(track = track, trackSource = source)
        val firstTime = elements("when", text).map { it.trim() }.filter { it.isNotEmpty() }.minOrNull()

        for (html in descriptions) flight = read(html, flight)
        if (flight.departureDate == null && firstTime != null) {
            DATE_AT_START.find(firstTime)?.let { flight = flight.copy(departureDate = it.groupValues[1]) }
        }
        if (flight.origin == null || flight.destination == null) {
            val places = listOfNotNull(flight.title) + descriptions.map(::plainText)
            for (place in places) {
                val route = ROUTE.find(place) ?: continue
                flight = flight.copy(
                    origin = flight.origin ?: KmlAirport(iata = route.groupValues[1]),
                    destination = flight.destination ?: KmlAirport(iata = route.groupValues[2]),
                )
                break
            }
        }
        return flight
    }

    // Description -------------------------------------------------------------------------------------------------

    private val DATE_AT_START = Regex("^(\\d{4}-\\d{2}-\\d{2})")
    private val ROUTE = Regex("\\b([A-Z]{3})\\s*[-–]\\s*([A-Z]{3})\\b")
    private val FLIGHT_PAGE = Regex("(https?://(?:www\\.)?flightradar24\\.com/(?:data/)?flights?/([A-Za-z0-9]+))")
    private val FLIGHT_LINK = Regex("(https?://(?:www\\.)?flightradar24\\.com/([A-Za-z0-9]{2,3}\\d{1,4}[A-Za-z]?)/[0-9a-fA-F]{6,})")
    private val REGISTRATION = Regex("/reg/([A-Za-z0-9-]{2,10})")
    private val AIRLINE = Regex("Airline:\\s*<b>([^<]+)</b>")
    private val AIRCRAFT = Regex("Aircraft:\\s*<b>([^<]*?)\\s*\\(([A-Za-z0-9]{2,4})\\)\\s*</b>")
    private val FROM = Regex("From:\\s*<b>([^<]*?)\\s*\\(([A-Za-z]{3,4})\\)\\s*</b>")
    private val TO = Regex("To:\\s*<b>([^<]*?)\\s*\\(([A-Za-z]{3,4})\\)\\s*</b>")
    private val DEPARTURE = Regex("Departure:\\s*<b>\\s*(\\d{4}-\\d{2}-\\d{2})(?:[ T]+(\\d{1,2}:\\d{2}))?")
    private val ATD = Regex("ATD\\s+(\\d{1,2}:\\d{2})")
    private val ETA = Regex("ETA\\s+(\\d{1,2}:\\d{2})")
    private val TITLE_ATTRIBUTE = Regex("title=\"([^\"]*)\"")
    private val IATA_HEADING = Regex("<h3>\\s*([A-Za-z]{3})\\s*</h3>")
    private val CITY_AFTER_HEADING = Regex("</h3>\\s*<[A-Za-z]+[^>]*>([^<]+)<")

    private fun read(html: String, start: KmlFlight): KmlFlight {
        var flight = start
        if (flight.flightLink == null) {
            val match = FLIGHT_PAGE.find(html) ?: FLIGHT_LINK.find(html)
            if (match != null) flight = flight.copy(flightLink = match.groupValues[1], flightNumber = flight.flightNumber ?: match.groupValues[2].uppercase())
        }
        if (flight.registration == null) REGISTRATION.find(html)?.let { flight = flight.copy(registration = it.groupValues[1].uppercase()) }
        if (flight.airline == null) AIRLINE.find(html)?.let { flight = flight.copy(airline = clean(it.groupValues[1])) }
        if (flight.aircraftTypeCode == null) AIRCRAFT.find(html)?.let {
            flight = flight.copy(aircraftTypeName = nonEmpty(clean(it.groupValues[1])), aircraftTypeCode = it.groupValues[2].uppercase())
        }

        // The older layout: "From: <b>Name (IATA)</b>", "To: ...", "Departure: <b>YYYY-MM-DD HH:MM</b>".
        if (flight.origin == null) FROM.find(html)?.let { flight = flight.copy(origin = airport(it.groupValues[1], it.groupValues[2])) }
        if (flight.destination == null) TO.find(html)?.let { flight = flight.copy(destination = airport(it.groupValues[1], it.groupValues[2])) }
        if (flight.departureDate == null) DEPARTURE.find(html)?.let {
            flight = flight.copy(departureDate = it.groupValues[1], departureTime = flight.departureTime ?: it.groupValues[2].ifEmpty { null })
        }

        // The newer layout: airport links with the name in `title`, then `<h3>IATA</h3>` and the city.
        if (flight.origin == null) flight = flight.copy(origin = linkedAirport("departures", html))
        if (flight.destination == null) flight = flight.copy(destination = linkedAirport("arrivals", html))
        if (flight.departureTime == null) ATD.find(html)?.let { flight = flight.copy(departureTime = it.groupValues[1]) }
        if (flight.arrivalTime == null) ETA.find(html)?.let { flight = flight.copy(arrivalTime = it.groupValues[1]) }
        return flight
    }

    private fun airport(name: String, code: String): KmlAirport =
        if (code.length == 3) KmlAirport(iata = code.uppercase(), name = nonEmpty(clean(name)))
        else KmlAirport(icao = code.uppercase(), name = nonEmpty(clean(name)))

    private fun linkedAirport(direction: String, html: String): KmlAirport? {
        val tag = Regex("<a\\s[^>]*href=\"[^\"]*/airports?/([A-Za-z0-9]+)/$direction\"[^>]*>").find(html) ?: return null
        val code = tag.groupValues[1]
        var result = KmlAirport(icao = if (code.length == 4) code.uppercase() else null)
        TITLE_ATTRIBUTE.find(tag.value)?.let { result = result.copy(name = nonEmpty(clean(it.groupValues[1]))) }
        val rest = html.substring(tag.range.last + 1).take(600)
        val iata = IATA_HEADING.find(rest)
        if (iata != null) {
            result = result.copy(iata = iata.groupValues[1].uppercase())
            CITY_AFTER_HEADING.find(rest)?.let { result = result.copy(city = nonEmpty(clean(it.groupValues[1]))) }
        } else if (code.length == 3) {
            result = result.copy(iata = code.uppercase())
        }
        return if (result.isEmpty) null else result
    }

    // Track -------------------------------------------------------------------------------------------------------

    private fun findTrack(text: String): Pair<List<GeoCoordinate>, KmlTrackSource> {
        var best = emptyList<GeoCoordinate>()
        for (block in elements("coordinates", text)) {
            val points = parseCoordinates(block)
            if (points.size >= MINIMUM_LINE_POINTS && points.size > best.size) best = points
        }
        if (best.isNotEmpty()) return best to KmlTrackSource.LINE

        class Report(val time: String, val index: Int, val point: GeoCoordinate)
        val reports = elements("Placemark", text).mapIndexedNotNull { index, placemark ->
            val time = elements("when", placemark).firstOrNull()?.trim()?.takeIf { it.isNotEmpty() } ?: return@mapIndexedNotNull null
            val point = elements("coordinates", placemark).firstOrNull()?.let(::parseCoordinates)?.firstOrNull() ?: return@mapIndexedNotNull null
            Report(time, index, point)
        }
        if (reports.size >= 2) return reports.sortedWith(compareBy({ it.time }, { it.index })).map { it.point } to KmlTrackSource.PLACEMARKS
        return emptyList<GeoCoordinate>() to KmlTrackSource.NONE
    }

    /** `lon,lat[,altitude]` separated by white space. A position that is not a valid coordinate is skipped. */
    fun parseCoordinates(text: String): List<GeoCoordinate> {
        val points = ArrayList<GeoCoordinate>()
        for (token in text.split(' ', '\n', '\r', '\t')) {
            if (token.isEmpty()) continue
            val parts = token.split(',')
            if (parts.size < 2) continue
            val lon = parts[0].toDoubleOrNull() ?: continue
            val lat = parts[1].toDoubleOrNull() ?: continue
            if (kotlin.math.abs(lon) > 180 || kotlin.math.abs(lat) > 90) continue
            points.add(GeoCoordinate(lat, lon))
        }
        return points
    }

    // Text helpers ------------------------------------------------------------------------------------------------

    /** The text inside every `<name ...>...</name>`, in file order. */
    internal fun elements(name: String, text: String): List<String> {
        val result = ArrayList<String>()
        var cursor = 0
        val open = "<$name"
        val close = "</$name>"
        while (true) {
            val start = text.indexOf(open, cursor)
            if (start < 0) break
            val next = start + open.length
            if (next >= text.length || text[next] !in "> \n\r\t/") { cursor = next; continue }
            val tagEnd = text.indexOf('>', next)
            if (tagEnd < 0) break
            if (text[tagEnd - 1] == '/') { cursor = tagEnd + 1; continue }
            val end = text.indexOf(close, tagEnd + 1)
            if (end < 0) break
            result.add(text.substring(tagEnd + 1, end))
            cursor = end + close.length
        }
        return result
    }

    /** The HTML in a description: the inside of a CDATA section as it is, otherwise the text with its entities decoded. */
    private fun descriptionHtml(raw: String): String {
        val trimmed = raw.trim()
        val open = trimmed.indexOf("<![CDATA[")
        val close = trimmed.lastIndexOf("]]>")
        if (open >= 0 && close >= open + 9) return trimmed.substring(open + 9, close)
        return unescape(trimmed)
    }

    private fun plainText(html: String) = html.replace(Regex("<[^>]*>"), " ")

    private fun unescape(text: String): String {
        if (!text.contains('&')) return text
        return text.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&#39;", "'").replace("&apos;", "'").replace("&amp;", "&")
    }

    private fun clean(text: String) = unescape(text).trim()

    private fun nonEmpty(text: String) = text.ifEmpty { null }
}
