package site.wingspot.core

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.tan

/** The smallest box around a track. */
data class TrackBox(val minLatitude: Double, val minLongitude: Double, val maxLatitude: Double, val maxLongitude: Double)

/** How much longer the flown way was than the great circle. */
data class Detour(val extraKm: Double, val percent: Double)

/** A flown route as the flight page shows it. [extraKm] and [percent] are 0 when there is no clear detour. */
data class FlownRoute(val flownKm: Int, val extraKm: Int, val percent: Int)

/**
 * Maths for a flown track: a list of positions in the order they were flown. It knows nothing about where the positions
 * came from, so any source can use it. Shared with the iPhone app and checked against `contracts/test-vectors/tracks.json`.
 */
object FlightTrack {
    /** The latitude where Web Mercator ends. */
    private const val MERCATOR_LIMIT = 85.05
    private const val EARTH_RADIUS_METERS = GreatCircle.EARTH_RADIUS_KM * 1000

    /** The length in kilometres: the haversine distances between neighbouring positions added up. The date line needs no
     *  special care, because the haversine of 358° and 2° apart is the same. */
    fun lengthKm(points: List<GeoCoordinate>): Double =
        points.zipWithNext().sumOf { (a, b) -> GreatCircle.distanceKm(a, b) }

    /** The same positions with longitudes that never jump: each one is shifted by a multiple of 360° to lie closest to the
     *  one before. A flight across the date line then has longitudes above 180° (or below -180°) instead of a jump. */
    fun unwrapped(points: List<GeoCoordinate>): List<GeoCoordinate> {
        if (points.isEmpty()) return emptyList()
        val result = ArrayList<GeoCoordinate>(points.size)
        result.add(points[0])
        var previous = points[0].longitude
        for (point in points.drop(1)) {
            val shifted = point.longitude + ((previous - point.longitude) / 360).roundHalfAwayFromZero() * 360
            result.add(GeoCoordinate(point.latitude, shifted))
            previous = shifted
        }
        return result
    }

    /** Whether the track passes the 180° meridian. */
    fun crossesAntimeridian(points: List<GeoCoordinate>): Boolean =
        points.zipWithNext().any { (a, b) -> GreatCircle.crossesAntimeridian(a, b) }

    /** A lighter track that looks the same on a map. The longitudes are unwrapped first, so the result is one continuous
     *  line. The first and last position are kept. Positions are dropped with Ramer–Douglas–Peucker on Web Mercator metres,
     *  with the tolerance scaled by cos(latitude), so [toleranceMeters] means metres on the ground everywhere. */
    fun simplified(points: List<GeoCoordinate>, toleranceMeters: Double): List<GeoCoordinate> {
        val track = unwrapped(points)
        if (track.size <= 2) return track
        val plane = track.map(::project)
        val keep = BooleanArray(track.size)
        keep[0] = true
        keep[track.size - 1] = true
        val ranges = ArrayDeque<Pair<Int, Int>>()
        ranges.addLast(0 to track.size - 1)
        while (ranges.isNotEmpty()) {
            val (first, last) = ranges.removeLast()
            var worst = -1.0
            var worstIndex = -1
            for (index in first + 1 until last) {
                val ground = distanceToSegment(plane[index], plane[first], plane[last]) * cos(Math.toRadians(clampedLatitude(track[index].latitude)))
                if (ground > worst) { worst = ground; worstIndex = index }
            }
            if (worstIndex >= 0 && worst > toleranceMeters) {
                keep[worstIndex] = true
                ranges.addLast(first to worstIndex)
                ranges.addLast(worstIndex to last)
            }
        }
        return track.filterIndexed { index, _ -> keep[index] }
    }

    /** The smallest box around the track, with longitudes unwrapped. Null for an empty track. */
    fun boundingBox(points: List<GeoCoordinate>): TrackBox? {
        val track = unwrapped(points)
        if (track.isEmpty()) return null
        return TrackBox(
            minLatitude = track.minOf { it.latitude }, minLongitude = track.minOf { it.longitude },
            maxLatitude = track.maxOf { it.latitude }, maxLongitude = track.maxOf { it.longitude },
        )
    }

    /** How much longer the flown way was than the great circle: the extra kilometres and the extra as a percentage of the
     *  great circle. Null when there is no great-circle distance to compare with. */
    fun detour(flownKm: Double, greatCircleKm: Double): Detour? {
        if (greatCircleKm <= 0) return null
        val extra = flownKm - greatCircleKm
        return Detour(extra, extra / greatCircleKm * 100)
    }

    /**
     * What a flight page shows about a flown route: its length in whole kilometres and, when it is clearly longer than the
     * airport-to-airport distance, how much more that is. Null for fewer than two positions.
     */
    fun flownRoute(points: List<GeoCoordinate>, greatCircleKm: Int?): FlownRoute? {
        if (points.size < 2) return null
        val flown = lengthKm(points)
        val flownKm = flown.roundHalfUp().toInt()
        val detour = greatCircleKm?.let { detour(flown, it.toDouble()) }
        if (detour == null || detour.extraKm < 1) return FlownRoute(flownKm, 0, 0)
        return FlownRoute(flownKm, detour.extraKm.roundHalfUp().toInt(), detour.percent.roundHalfUp().toInt())
    }

    /** Rounds .5 away from zero, as the iPhone app does, so both apps shift a point at exactly 180° the same way. */
    private fun Double.roundHalfAwayFromZero(): Double = if (this < 0) -((-this).roundHalfUp()) else roundHalfUp()
    private fun Double.roundHalfUp(): Double = kotlin.math.floor(this + 0.5)

    private fun clampedLatitude(latitude: Double) = min(MERCATOR_LIMIT, max(-MERCATOR_LIMIT, latitude))

    private fun project(point: GeoCoordinate): Pair<Double, Double> {
        val latitude = Math.toRadians(clampedLatitude(point.latitude))
        return EARTH_RADIUS_METERS * Math.toRadians(point.longitude) to EARTH_RADIUS_METERS * ln(tan(PI / 4 + latitude / 2))
    }

    private fun distanceToSegment(p: Pair<Double, Double>, a: Pair<Double, Double>, b: Pair<Double, Double>): Double {
        val dx = b.first - a.first
        val dy = b.second - a.second
        val lengthSquared = dx * dx + dy * dy
        if (lengthSquared <= 0) return hypot(p.first - a.first, p.second - a.second)
        val t = max(0.0, min(1.0, ((p.first - a.first) * dx + (p.second - a.second) * dy) / lengthSquared))
        return hypot(p.first - a.first - t * dx, p.second - a.second - t * dy)
    }
}
