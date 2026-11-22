package site.wingspot.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import site.wingspot.core.GeoCoordinate
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.geometry.Offset
import androidx.compose.foundation.Canvas
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.MapUiSettings
import com.google.maps.android.compose.Marker
import com.google.maps.android.compose.Polyline
import com.google.maps.android.compose.MarkerState
import com.google.maps.android.compose.rememberCameraPositionState
import site.wingspot.core.Airport
import site.wingspot.core.ApiException
import site.wingspot.core.CheckInStats
import site.wingspot.core.LocalCheckIn

/** An airport on a map. [busy] ones are orange, the others blue, like on the iPhone. */
data class AirportMarker(val airport: Airport, val busy: Boolean)

private const val ORANGE_HUE = BitmapDescriptorFactory.HUE_ORANGE
private const val BLUE_HUE = BitmapDescriptorFactory.HUE_AZURE

/** The ids of the airports you spotted at or visited, from the check-ins on this phone. */
fun airportIdsOf(local: List<LocalCheckIn>): Set<Long> =
    CheckInStats.counted(local).filter { it.kind != "flown" }.mapNotNull { it.airportId }.toSet()

/** The map, or a note when this build has no Google Maps key. Tapping a marker's name opens the airport. */
@Composable
fun AirportMap(markers: List<AirportMarker>, modifier: Modifier = Modifier, interactive: Boolean = true, onOpen: (Long) -> Unit = {}) {
    if (!BuildConfig.MAPS_KEY_SET) {
        Box(modifier.clip(MaterialTheme.shapes.medium), contentAlignment = Alignment.Center) {
            Text(stringResource(R.string.map_not_set_up), modifier = Modifier.padding(16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        return
    }
    val camera = rememberCameraPositionState { position = CameraPosition.fromLatLngZoom(LatLng(30.0, 10.0), 1.5f) }
    LaunchedEffect(markers) {
        when {
            markers.isEmpty() -> Unit
            markers.size == 1 -> camera.move(CameraUpdateFactory.newLatLngZoom(LatLng(markers[0].airport.latitude, markers[0].airport.longitude), 9f))
            else -> {
                val bounds = LatLngBounds.builder().apply { markers.forEach { include(LatLng(it.airport.latitude, it.airport.longitude)) } }.build()
                try { camera.move(CameraUpdateFactory.newLatLngBounds(bounds, 96)) } catch (e: Exception) { /* the map isn't laid out yet: the default view stays */ }
            }
        }
    }
    GoogleMap(
        modifier = modifier, cameraPositionState = camera, properties = MapProperties(),
        uiSettings = MapUiSettings(zoomControlsEnabled = interactive, scrollGesturesEnabled = interactive, zoomGesturesEnabled = interactive, rotationGesturesEnabled = false, tiltGesturesEnabled = false, mapToolbarEnabled = false),
    ) {
        for (m in markers) {
            Marker(
                state = MarkerState(LatLng(m.airport.latitude, m.airport.longitude)), title = m.airport.code, snippet = m.airport.name,
                icon = BitmapDescriptorFactory.defaultMarker(if (m.busy) ORANGE_HUE else BLUE_HUE),
                onInfoWindowClick = { onOpen(m.airport.id) },
            )
        }
    }
}

/** A small map of one airport, for its page. It doesn't move. */
@Composable
fun AirportMiniMap(airport: Airport) {
    AirportMap(listOf(AirportMarker(airport, false)), Modifier.fillMaxWidth().height(160.dp).clip(MaterialTheme.shapes.medium), interactive = false)
}

/** A map of the airports you checked in at. The positions come from the downloaded airport data, so it works offline. */
@Composable
fun AirportsMapPage(local: List<LocalCheckIn>, reference: ReferenceState, social: SocialViewModel) {
    val ids = airportIdsOf(local)
    var markers by remember { mutableStateOf<List<AirportMarker>?>(null) }
    LaunchedEffect(ids, reference.database) {
        val db = reference.database ?: run { markers = emptyList(); return@LaunchedEffect }
        markers = ids.sorted().mapNotNull { db.airport(it) }.map { AirportMarker(it, false) }
    }
    Column(Modifier.fillMaxSize()) {
        PageHeader(stringResource(R.string.airports_map), social::back)
        MapOrNote(markers, reference, R.string.no_airports_yet) { social.open(Route.AirportPage(it)) }
    }
}

/** The airports that were busy this week (orange) and the ones you checked in at (blue). Tapping a marker's label opens the airport. */
@Composable
fun ExploreMapPage(app: WingspotApp, me: String?, local: List<LocalCheckIn>, reference: ReferenceState, social: SocialViewModel) {
    val ids = airportIdsOf(local)
    var markers by remember { mutableStateOf<List<AirportMarker>?>(null) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(ids, reference.database, me) {
        val db = reference.database ?: run { markers = emptyList(); return@LaunchedEffect }
        var busy = emptySet<Long>()
        failed = false
        if (me != null && app.terms.hasAccepted(me)) {
            try { busy = app.social.activeAirports(7, 30).map { it.airportId }.toSet() } catch (e: ApiException) { failed = true }
        }
        markers = (busy + ids).sorted().mapNotNull { id -> db.airport(id)?.let { AirportMarker(it, id in busy) } }
    }
    Column(Modifier.fillMaxSize()) {
        PageHeader(stringResource(R.string.map), social::back)
        MapOrNote(markers, reference, R.string.no_airports_to_show) { social.open(Route.AirportPage(it)) }
        Column(Modifier.fillMaxWidth().padding(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Text("● " + stringResource(R.string.busy_this_week), color = androidx.compose.ui.graphics.Color(0xFFFF9500), style = MaterialTheme.typography.bodySmall)
                Text("● " + stringResource(R.string.yours), color = androidx.compose.ui.graphics.Color(0xFF007AFF), style = MaterialTheme.typography.bodySmall)
            }
            if (failed) Text(stringResource(R.string.busy_load_failed), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.ColumnScope.MapOrNote(markers: List<AirportMarker>?, reference: ReferenceState, emptyText: Int, onOpen: (Long) -> Unit) {
    when {
        markers == null -> Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        markers.isEmpty() -> Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
            Text(stringResource(if (reference.database == null) R.string.map_needs_data else emptyText), modifier = Modifier.padding(24.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        else -> AirportMap(markers, Modifier.fillMaxWidth().weight(1f), onOpen = onOpen)
    }
}

/**
 * The flown route of an imported flight: the simplified line with a start and an end marker, zoomed to fit. With a
 * Google Maps key it is a map; without one the route is drawn by itself on a plain background, so it still shows.
 */
@Composable
fun TrackMap(line: List<GeoCoordinate>, modifier: Modifier = Modifier) {
    val description = stringResource(R.string.route_map_description)
    if (line.size < 2) return
    if (!BuildConfig.MAPS_KEY_SET) {
        RouteSketch(line, modifier.semantics { contentDescription = description })
        return
    }
    val camera = rememberCameraPositionState { position = CameraPosition.fromLatLngZoom(LatLng(line.first().latitude, line.first().longitude), 4f) }
    val points = remember(line) { line.map { LatLng(it.latitude.coerceIn(-85.0, 85.0), it.longitude) } }
    LaunchedEffect(points) {
        val bounds = LatLngBounds.builder().apply { points.forEach { include(it) } }.build()
        try { camera.move(CameraUpdateFactory.newLatLngBounds(bounds, 64)) } catch (e: Exception) { /* the map isn't laid out yet: the first position stays */ }
    }
    val color = MaterialTheme.colorScheme.primary
    GoogleMap(
        modifier = modifier.semantics { contentDescription = description }, cameraPositionState = camera, properties = MapProperties(),
        uiSettings = MapUiSettings(zoomControlsEnabled = false, scrollGesturesEnabled = false, zoomGesturesEnabled = false, rotationGesturesEnabled = false, tiltGesturesEnabled = false, mapToolbarEnabled = false),
    ) {
        Polyline(points = points, color = color, width = 8f)
        Marker(state = MarkerState(points.first()), icon = BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_GREEN))
        Marker(state = MarkerState(points.last()), icon = BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_RED))
    }
}

/** The route drawn on a plain background: longitudes are unwrapped, so a flight over the date line is one line. */
@Composable
private fun RouteSketch(line: List<GeoCoordinate>, modifier: Modifier = Modifier) {
    val track = remember(line) { site.wingspot.core.FlightTrack.unwrapped(line) }
    val color = MaterialTheme.colorScheme.primary
    val background = MaterialTheme.colorScheme.surfaceVariant
    Canvas(modifier.clip(MaterialTheme.shapes.medium)) {
        drawRect(background)
        val minLon = track.minOf { it.longitude }
        val maxLon = track.maxOf { it.longitude }
        val minLat = track.minOf { it.latitude }
        val maxLat = track.maxOf { it.latitude }
        val squeeze = kotlin.math.cos(Math.toRadians((minLat + maxLat) / 2)).coerceAtLeast(0.2)
        val width = ((maxLon - minLon) * squeeze).coerceAtLeast(0.01)
        val height = (maxLat - minLat).coerceAtLeast(0.01)
        val pad = 24.dp.toPx()
        val scale = minOf((size.width - 2 * pad) / width, (size.height - 2 * pad) / height).toFloat()
        val left = (size.width - (width * scale).toFloat()) / 2
        val top = (size.height - (height * scale).toFloat()) / 2
        fun at(p: GeoCoordinate) = Offset(left + ((p.longitude - minLon) * squeeze * scale).toFloat(), top + ((maxLat - p.latitude) * scale).toFloat())
        val path = Path().apply { track.forEachIndexed { i, p -> val o = at(p); if (i == 0) moveTo(o.x, o.y) else lineTo(o.x, o.y) } }
        drawPath(path, color, style = Stroke(width = 3.dp.toPx()))
        drawCircle(Color(0xFF2E7D32), radius = 6.dp.toPx(), center = at(track.first()))
        drawCircle(Color(0xFFC62828), radius = 6.dp.toPx(), center = at(track.last()))
    }
}
