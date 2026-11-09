package site.wingspot.core

import kotlin.math.asin
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

data class GeoCoordinate(val latitude: Double, val longitude: Double)

/** Great-circle math for flown distances and route badges, checked against `contracts/test-vectors/distances.json`. */
object GreatCircle {
    /** Mean Earth radius (IUGG). */
    const val EARTH_RADIUS_KM = 6371.0088

    /** Haversine distance in kilometres. */
    fun distanceKm(from: GeoCoordinate, to: GeoCoordinate): Double {
        val lat1 = Math.toRadians(from.latitude)
        val lat2 = Math.toRadians(to.latitude)
        val dLat = lat2 - lat1
        val dLon = Math.toRadians(to.longitude - from.longitude)
        val h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * EARTH_RADIUS_KM * asin(min(1.0, sqrt(h)))
    }

    fun crossesEquator(from: GeoCoordinate, to: GeoCoordinate) = (from.latitude < 0) != (to.latitude < 0)

    fun crossesAntimeridian(from: GeoCoordinate, to: GeoCoordinate) = abs(to.longitude - from.longitude) > 180
}
