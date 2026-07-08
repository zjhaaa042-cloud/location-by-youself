package com.example.locationmocker.presentation

import android.graphics.Color
import android.graphics.Point
import android.os.Bundle
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
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
    var handledTrackDetectionRequestId by remember { mutableStateOf(0) }
    val mapView = remember {
        MapsInitializer.updatePrivacyShow(context, true, true)
        MapsInitializer.updatePrivacyAgree(context, true)
        MapView(context).apply {
            onCreate(Bundle())
            map.uiSettings.isZoomControlsEnabled = false
            map.uiSettings.isScaleControlsEnabled = true
            map.uiSettings.isMyLocationButtonEnabled = true
            map.uiSettings.isCompassEnabled = true
            map.myLocationStyle = MyLocationStyle()
                .myLocationType(MyLocationStyle.LOCATION_TYPE_LOCATION_ROTATE_NO_CENTER)
                .interval(1_000L)
                .strokeColor(Color.rgb(21, 108, 94))
                .radiusFillColor(Color.argb(42, 21, 108, 94))
                .strokeWidth(2f)
            map.isMyLocationEnabled = true
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
            amap.clear()

            if (routeMode && points.size >= 2) {
                amap.addPolyline(
                    PolylineOptions()
                        .addAll(points.map { it.toLatLng() })
                        .color(Color.rgb(21, 108, 94))
                        .width(8f),
                )
            }

            if (traveledPoints.size >= 2) {
                amap.addPolyline(
                    PolylineOptions()
                        .addAll(traveledPoints.map { it.toLatLng() })
                        .color(Color.rgb(230, 81, 0))
                        .width(12f),
                )
            }

            if (showPointMarkers) {
                points.forEachIndexed { index, point ->
                    amap.addMarker(
                        MarkerOptions()
                            .position(point.toLatLng())
                            .title(if (routeMode) "\u9014\u7ecf\u70b9 ${index + 1}" else "\u6a21\u62df\u4f4d\u7f6e")
                            .snippet("%.6f, %.6f".format(point.lat, point.lon))
                            .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_AZURE)),
                    )
                }
            }

            currentPoint?.let { point ->
                amap.addMarker(
                    MarkerOptions()
                        .position(point.toLatLng())
                        .title("\u5b9e\u65f6\u6a21\u62df\u4f4d\u7f6e")
                        .snippet("%.6f, %.6f".format(point.lat, point.lon))
                        .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_ORANGE)),
                )
                amap.animateCamera(CameraUpdateFactory.newLatLng(point.toLatLng()))
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
