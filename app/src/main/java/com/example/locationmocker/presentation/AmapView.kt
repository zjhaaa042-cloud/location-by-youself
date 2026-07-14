package com.example.locationmocker.presentation

import android.graphics.Color
import android.graphics.Point
import android.os.Bundle
import android.view.MotionEvent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.amap.api.maps.AMap
import com.amap.api.maps.CameraUpdateFactory
import com.amap.api.maps.MapView
import com.amap.api.maps.MapsInitializer
import com.amap.api.maps.model.BitmapDescriptorFactory
import com.amap.api.maps.model.LatLng
import com.amap.api.maps.model.MarkerOptions
import com.amap.api.maps.model.MyLocationStyle
import com.amap.api.maps.model.Marker
import com.amap.api.maps.model.Polyline
import com.amap.api.maps.model.PolylineOptions
import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.domain.track.SegmentedTrack

@Composable
fun AmapView(
    points: List<RoutePoint>,
    devicePoint: RoutePoint?,
    currentPoint: RoutePoint?,
    traveledPoints: List<RoutePoint>,
    routeMode: Boolean,
    showPointMarkers: Boolean,
    enableTrackSegmentation: Boolean,
    locateDeviceRequestId: Int,
    trackDetectionRequestId: Int,
    trackDetectionTarget: RoutePoint?,
    onMapLoaded: () -> Unit,
    onDeviceLocationChanged: (lat: Double, lon: Double) -> Unit,
    onMapTapped: (lat: Double, lon: Double, segmentedTrack: SegmentedTrack?) -> Unit,
    onTrackDetectionRequested: (RoutePoint, SegmentedTrack?) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val currentEnableTrackSegmentation = rememberUpdatedState(enableTrackSegmentation)
    val currentOnMapTapped = rememberUpdatedState(onMapTapped)
    val currentTrackDetectionTarget = rememberUpdatedState(trackDetectionTarget)
    val currentOnTrackDetectionRequested = rememberUpdatedState(onTrackDetectionRequested)
    val cameraState = remember { MapCameraState() }
    val overlayState = remember { MapOverlayState() }
    var handledTrackDetectionRequestId by remember { mutableIntStateOf(0) }
    val mapView = remember {
        MapsInitializer.updatePrivacyShow(context, true, true)
        MapsInitializer.updatePrivacyAgree(context, true)
        MapView(context).apply {
            onCreate(Bundle())
            map.uiSettings.isZoomControlsEnabled = false
            map.uiSettings.isScaleControlsEnabled = true
            map.uiSettings.isMyLocationButtonEnabled = false
            map.uiSettings.isCompassEnabled = true
            map.uiSettings.isZoomGesturesEnabled = true
            map.uiSettings.isScrollGesturesEnabled = true
            map.myLocationStyle = MyLocationStyle()
                .myLocationType(MyLocationStyle.LOCATION_TYPE_LOCATION_ROTATE_NO_CENTER)
                .interval(1_000L)
                .strokeColor(Color.rgb(21, 108, 94))
                .radiusFillColor(Color.argb(42, 21, 108, 94))
                .strokeWidth(2f)
            map.isMyLocationEnabled = true
            map.setOnMapTouchListener { event ->
                parent?.requestDisallowInterceptTouchEvent(
                    event.actionMasked != MotionEvent.ACTION_UP &&
                        event.actionMasked != MotionEvent.ACTION_CANCEL,
                )
            }
            map.moveCamera(CameraUpdateFactory.newLatLngZoom(LatLng(31.2304, 121.4737), 14f))
            map.setOnMapLoadedListener { onMapLoaded() }
            map.setOnMyLocationChangeListener { location ->
                if (location != null) {
                    onDeviceLocationChanged(location.latitude, location.longitude)
                }
            }
            map.setOnMapClickListener { latLng ->
                if (!currentEnableTrackSegmentation.value) {
                    currentOnMapTapped.value(latLng.latitude, latLng.longitude, null)
                    return@setOnMapClickListener
                }
                val screenPoint = map.projection.toScreenLocation(latLng)
                map.captureSegmentedTrack(screenPoint) { segmented ->
                    currentOnMapTapped.value(latLng.latitude, latLng.longitude, segmented)
                }
            }
        }
    }

    DisposableEffect(lifecycleOwner, mapView) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> mapView.onResume()
                Lifecycle.Event.ON_PAUSE -> mapView.onPause()
                Lifecycle.Event.ON_DESTROY -> mapView.onDestroy()
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    AndroidView(
        modifier = modifier,
        factory = { mapView },
        update = { view ->
            val amap = view.map
            overlayState.render(
                amap = amap,
                points = points,
                currentPoint = currentPoint,
                traveledPoints = traveledPoints,
                routeMode = routeMode,
                showPointMarkers = showPointMarkers,
            )

            currentPoint?.let { point ->
                if (!cameraState.simulationActive) {
                    amap.animateCamera(CameraUpdateFactory.newLatLng(point.toLatLng()))
                }
            }
            cameraState.simulationActive = currentPoint != null

            if (
                locateDeviceRequestId > 0 &&
                locateDeviceRequestId != cameraState.handledLocateDeviceRequestId
            ) {
                devicePoint?.let { point ->
                    cameraState.handledLocateDeviceRequestId = locateDeviceRequestId
                    amap.animateCamera(CameraUpdateFactory.newLatLngZoom(point.toLatLng(), 16f))
                }
            }

            if (currentPoint == null && devicePoint == null) {
                // Keep the user's current zoom and viewport while selecting points.
            }

            if (
                trackDetectionRequestId > 0 &&
                trackDetectionRequestId != handledTrackDetectionRequestId
            ) {
                handledTrackDetectionRequestId = trackDetectionRequestId
                currentTrackDetectionTarget.value?.let { target ->
                    val screenPoint = amap.projection.toScreenLocation(target.toLatLng())
                    amap.captureSegmentedTrack(screenPoint) { segmented ->
                        currentOnTrackDetectionRequested.value(target, segmented)
                    }
                }
            }
        },
    )
}

private class MapCameraState {
    var simulationActive: Boolean = false
    var handledLocateDeviceRequestId: Int = 0
}

private class MapOverlayState {
    private var renderedPoints: List<RoutePoint> = emptyList()
    private var renderedRouteMode: Boolean = false
    private var renderedShowPointMarkers: Boolean = false
    private var routePolyline: Polyline? = null
    private var traveledPolyline: Polyline? = null
    private var currentMarker: Marker? = null
    private val pointMarkers = mutableListOf<Marker>()

    fun render(
        amap: AMap,
        points: List<RoutePoint>,
        currentPoint: RoutePoint?,
        traveledPoints: List<RoutePoint>,
        routeMode: Boolean,
        showPointMarkers: Boolean,
    ) {
        if (
            points != renderedPoints ||
            routeMode != renderedRouteMode ||
            showPointMarkers != renderedShowPointMarkers
        ) {
            routePolyline?.remove()
            routePolyline = if (routeMode && points.size >= 2) {
                amap.addPolyline(
                    PolylineOptions()
                        .addAll(points.map { it.toLatLng() })
                        .color(Color.rgb(21, 108, 94))
                        .width(8f),
                )
            } else {
                null
            }
            pointMarkers.forEach(Marker::remove)
            pointMarkers.clear()
            if (showPointMarkers) {
                points.forEachIndexed { index, point ->
                    pointMarkers += amap.addMarker(
                        MarkerOptions()
                            .position(point.toLatLng())
                            .title(if (routeMode) "途经点 ${index + 1}" else "模拟位置")
                            .snippet("%.6f, %.6f".format(point.lat, point.lon))
                            .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_AZURE)),
                    )
                }
            }
            renderedPoints = points.toList()
            renderedRouteMode = routeMode
            renderedShowPointMarkers = showPointMarkers
        }

        if (traveledPoints.size >= 2) {
            val latLngs = traveledPoints.map { it.toLatLng() }
            val existing = traveledPolyline
            if (existing == null) {
                traveledPolyline = amap.addPolyline(
                    PolylineOptions()
                        .addAll(latLngs)
                        .color(Color.rgb(230, 81, 0))
                        .width(12f),
                )
            } else {
                existing.points = latLngs
            }
        } else {
            traveledPolyline?.remove()
            traveledPolyline = null
        }

        if (currentPoint == null) {
            currentMarker?.remove()
            currentMarker = null
        } else {
            val existing = currentMarker
            if (existing == null) {
                currentMarker = amap.addMarker(
                    MarkerOptions()
                        .position(currentPoint.toLatLng())
                        .title("实时模拟位置")
                        .snippet("%.6f, %.6f".format(currentPoint.lat, currentPoint.lon))
                        .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_ORANGE)),
                )
            } else {
                existing.position = currentPoint.toLatLng()
            }
        }
    }
}

private fun RoutePoint.toLatLng(): LatLng = LatLng(lat, lon)
private fun LatLng.toRoutePoint(): RoutePoint = RoutePoint(latitude, longitude)

private fun AMap.captureSegmentedTrack(
    screenPoint: Point,
    onResult: (SegmentedTrack?) -> Unit,
) {
    var handled = false
    fun handleScreenshot(bitmap: android.graphics.Bitmap?) {
        if (handled) return
        handled = true
        val segmented = bitmap?.let {
            TrackMapSegmenter.segment(
                bitmap = it,
                tapPoint = screenPoint,
                pixelToRoutePoint = { point ->
                    runCatching {
                        projection.fromScreenLocation(Point(point.x, point.y)).toRoutePoint()
                    }.getOrNull()
                },
            )
        }
        onResult(segmented)
    }
    getMapScreenShot(
        object : AMap.OnMapScreenShotListener {
            override fun onMapScreenShot(bitmap: android.graphics.Bitmap?) {
                handleScreenshot(bitmap)
            }

            override fun onMapScreenShot(bitmap: android.graphics.Bitmap?, status: Int) {
                handleScreenshot(bitmap)
            }
        },
    )
}
