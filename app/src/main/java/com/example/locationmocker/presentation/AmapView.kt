package com.example.locationmocker.presentation

import android.graphics.Color
import android.os.Bundle
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.amap.api.maps.CameraUpdateFactory
import com.amap.api.maps.MapView
import com.amap.api.maps.MapsInitializer
import com.amap.api.maps.model.BitmapDescriptorFactory
import com.amap.api.maps.model.LatLng
import com.amap.api.maps.model.MarkerOptions
import com.amap.api.maps.model.MyLocationStyle
import com.amap.api.maps.model.PolylineOptions
import com.example.locationmocker.domain.model.RoutePoint

@Composable
fun AmapView(
    points: List<RoutePoint>,
    devicePoint: RoutePoint?,
    currentPoint: RoutePoint?,
    traveledPoints: List<RoutePoint>,
    routeMode: Boolean,
    onMapLoaded: () -> Unit,
    onDeviceLocationChanged: (lat: Double, lon: Double) -> Unit,
    onMapTapped: (lat: Double, lon: Double) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
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
            map.setOnMapLoadedListener {
                onMapLoaded()
            }
            map.setOnMyLocationChangeListener { location ->
                if (location != null) {
                    onDeviceLocationChanged(location.latitude, location.longitude)
                }
            }
            map.setOnMapClickListener { latLng ->
                onMapTapped(latLng.latitude, latLng.longitude)
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

            points.forEachIndexed { index, point ->
                amap.addMarker(
                    MarkerOptions()
                        .position(point.toLatLng())
                        .title(if (routeMode) "途经点 ${index + 1}" else "模拟位置")
                        .snippet("%.6f, %.6f".format(point.lat, point.lon))
                        .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_AZURE)),
                )
            }

            currentPoint?.let { point ->
                amap.addMarker(
                    MarkerOptions()
                        .position(point.toLatLng())
                        .title("实时模拟位置")
                        .snippet("%.6f, %.6f".format(point.lat, point.lon))
                        .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_ORANGE)),
                )
            }

            val focusPoint = currentPoint ?: points.lastOrNull() ?: devicePoint
            focusPoint?.let { point ->
                amap.animateCamera(CameraUpdateFactory.newLatLngZoom(point.toLatLng(), 16f))
            }
        },
    )
}

private fun RoutePoint.toLatLng(): LatLng = LatLng(lat, lon)
