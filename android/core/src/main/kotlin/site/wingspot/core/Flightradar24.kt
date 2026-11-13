package site.wingspot.core

/** Where to look a flight or an aircraft up on Flightradar24. Wingspot sends nothing there: the link only opens the page. */
object Flightradar24 {
    /** The page of a flight number such as `LH400`, which lists the aircraft that flew it. */
    fun flight(flightNumber: String): String? {
        val code = flightNumber.filter { it.isLetterOrDigit() }.lowercase()
        return if (code.isEmpty()) null else "https://www.flightradar24.com/data/flights/$code"
    }

    /** The page of a registration such as `D-AIMA`, with its type and history. */
    fun aircraft(registration: String): String? {
        val code = registration.trim().lowercase()
        return if (code.isEmpty()) null else "https://www.flightradar24.com/data/aircraft/$code"
    }
}
