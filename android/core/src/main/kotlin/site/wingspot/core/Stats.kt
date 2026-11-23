package site.wingspot.core

import java.time.Instant
import java.util.UUID

/**
 * The numbers on the profile, worked out from the check-ins on this phone so they work offline.
 * Check-ins the server refused are left out, because the server doesn't count them either.
 */
data class CheckInStats(
    val checkIns: Int = 0,
    val sightings: Int = 0,
    val airportVisits: Int = 0,
    val flights: Int = 0,
    /** Different registrations seen. */
    val aircraft: Int = 0,
    /** Different aircraft types, from sightings and flights. */
    val types: Int = 0,
    /** The airports checked in at, including the two airports a flight checks in. */
    val airports: Int = 0,
    /** How many flights were flown between each pair of airports (origin id, destination id). */
    val routes: Map<Pair<Long, Long>, Int> = emptyMap(),
    /** Every flight with its two airports, to look for its saved route. */
    val flightList: List<FlightRef> = emptyList(),
) {
    /** A flight and its airports. */
    data class FlightRef(val id: java.util.UUID, val origin: Long, val destination: Long)

    /**
     * The kilometres flown: the great-circle distance of each flight, rounded as the server does.
     * Flights whose airports are not known are left out.
     */
    fun kilometres(coordinate: (Long) -> GeoCoordinate?): Int = routes.entries.sumOf { (route, count) ->
        val from = coordinate(route.first)
        val to = coordinate(route.second)
        if (from == null || to == null) 0 else Math.round(GreatCircle.distanceKm(from, to)).toInt() * count
    }

    companion object {
        fun counted(all: List<LocalCheckIn>) = all.filter { it.syncState != SyncState.REJECTED }

        fun of(all: List<LocalCheckIn>): CheckInStats {
            val registrations = mutableSetOf<String>()
            val types = mutableSetOf<String>()
            val airports = mutableSetOf<Long>()
            var sightings = 0
            var visits = 0
            var flights = 0
            val routes = mutableMapOf<Pair<Long, Long>, Int>()
            val flightList = mutableListOf<FlightRef>()
            val counted = counted(all)
            for (c in counted) {
                when (c.kind) {
                    "spotted" -> { sightings++; c.airportId?.let(airports::add) }
                    "airport" -> { visits++; c.airportId?.let(airports::add) }
                    "flown" -> {
                        flights++
                        val origin = c.originId
                        val destination = c.destinationId
                        if (origin != null && destination != null) {
                            routes.merge(origin to destination, 1, Int::plus)
                            flightList.add(FlightRef(c.id, origin, destination))
                        }
                    }
                }
                c.registration?.let(registrations::add)
                c.typeIcao?.let(types::add)
            }
            return CheckInStats(counted.size, sightings, visits, flights, registrations.size, types.size, airports.size, routes, flightList)
        }
    }
}

/** The aircraft types of earlier flights with a flight number, to offer when the same flight is checked in again. */
object RecentTypes {
    /** The aircraft types you checked in most recently, newest first, each once, from sightings and flights. */
    fun types(all: List<LocalCheckIn>, limit: Int = 5): List<String> =
        CheckInStats.counted(all).filter { it.typeIcao != null }.sortedByDescending { it.occurredAt }
            .mapNotNull { it.typeIcao }.distinct().take(limit)

    /** The airports you checked in at most recently, newest first, each once, including where your flights started and ended. */
    fun airportIds(all: List<LocalCheckIn>, limit: Int = 5): List<Long> =
        CheckInStats.counted(all).sortedByDescending { it.occurredAt }
            .flatMap { if (it.kind == "flown") listOf(it.destinationId, it.originId) else listOf(it.airportId) }
            .filterNotNull().distinct().take(limit)

    /** ICAO codes, the most recent flight first, each once. The flight being edited, if any, is left out. */
    fun forFlight(all: List<LocalCheckIn>, flightNumber: String, excluding: UUID? = null, limit: Int = 5): List<String> {
        val number = flightNumber.filterNot { it.isWhitespace() }.uppercase()
        if (number.isEmpty()) return emptyList()
        return CheckInStats.counted(all)
            .filter { it.kind == "flown" && it.flightNumber == number && it.typeIcao != null && it.id != excluding }
            .sortedByDescending { it.occurredAt }
            .mapNotNull { it.typeIcao }
            .distinct()
            .take(limit)
    }
}

/** What has been seen, how often and when last. */
/** The kind of entry in the collections. */
enum class CollectionKind { AIRCRAFT, TYPE, AIRPORT }

/** Which date a list is sorted by: the date of the flight or sighting, or the check-in date ([LocalCheckIn.enteredAt]). */
enum class CollectionDateKind { FLIGHT, CHECK_IN }

data class CollectionEntry(val id: String, val title: String, val count: Int, val lastSeen: Instant)

data class Collections(val aircraft: List<CollectionEntry>, val types: List<CollectionEntry>, val airports: List<CollectionEntry>) {
    companion object {
        private data class Keys(val aircraft: String?, val type: String?, val airport: String?)

        /**
         * Which entries a check-in belongs to. The counts and [checkIns] both use this, so the number of listed check-ins
         * always matches the count of the entry. A flight has no airport of its own; its two airports are check-ins of their own.
         */
        private fun keysOf(c: LocalCheckIn) = Keys(c.registration, c.typeIcao, if (c.kind != "flown") c.airportCode else null)

        /** The check-ins behind one entry of a list: all that count towards it, in no particular order (see [ordered]). */
        fun checkIns(kind: CollectionKind, key: String, all: List<LocalCheckIn>): List<LocalCheckIn> = CheckInStats.counted(all).filter {
            val keys = keysOf(it)
            when (kind) { CollectionKind.AIRCRAFT -> keys.aircraft == key; CollectionKind.TYPE -> keys.type == key; CollectionKind.AIRPORT -> keys.airport == key }
        }

        /** All flights, for the flights tab. */
        fun flights(all: List<LocalCheckIn>): List<LocalCheckIn> = CheckInStats.counted(all).filter { it.kind == "flown" }

        /** Sorted by the chosen date, then the other one and the id, so the order never flickers between equal dates. */
        fun ordered(list: List<LocalCheckIn>, by: CollectionDateKind, ascending: Boolean): List<LocalCheckIn> {
            fun date(c: LocalCheckIn) = if (by == CollectionDateKind.FLIGHT) c.occurredAt else c.enteredAt
            fun other(c: LocalCheckIn) = if (by == CollectionDateKind.FLIGHT) c.enteredAt else c.occurredAt
            val order = compareBy<LocalCheckIn>({ date(it) }, { other(it) }, { it.id.toString() })
            return list.sortedWith(if (ascending) order else order.reversed())
        }

        /** Each list is sorted by the number of check-ins, then by the most recent first. */
        fun of(all: List<LocalCheckIn>): Collections {
            val aircraft = mutableMapOf<String, CollectionEntry>()
            val types = mutableMapOf<String, CollectionEntry>()
            val airports = mutableMapOf<String, CollectionEntry>()
            fun add(key: String, at: Instant, into: MutableMap<String, CollectionEntry>) {
                val old = into[key]
                into[key] = if (old == null) CollectionEntry(key, key, 1, at) else old.copy(count = old.count + 1, lastSeen = maxOf(old.lastSeen, at))
            }
            for (c in CheckInStats.counted(all)) {
                keysOf(c).aircraft?.let { add(it, c.occurredAt, aircraft) }
                keysOf(c).type?.let { add(it, c.occurredAt, types) }
                keysOf(c).airport?.let { add(it, c.occurredAt, airports) }
            }
            val order = compareByDescending<CollectionEntry> { it.count }.thenByDescending { it.lastSeen }.thenBy { it.title }
            return Collections(aircraft.values.sortedWith(order), types.values.sortedWith(order), airports.values.sortedWith(order))
        }
    }
}

/** How distances are shown. The database always stores kilometres. */
enum class DistanceUnit(val symbol: String) {
    KILOMETRES("km"), NAUTICAL_MILES("NM"), MILES("mi");

    fun value(km: Int): Int = when (this) {
        KILOMETRES -> km
        NAUTICAL_MILES -> Math.round(km / 1.852).toInt()
        MILES -> Math.round(km / 1.609344).toInt()
    }

    fun format(km: Int): String = "%,d %s".format(value(km), symbol)
}
