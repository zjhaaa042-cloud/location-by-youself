package com.example.locationmocker.service

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.location.LocationManager
import android.os.SystemClock
import com.example.locationmocker.domain.geo.CoordinateTransform
import com.example.locationmocker.domain.model.RoutePoint

class MockLocationController(context: Context) {
    private val locationManager = context.getSystemService(LocationManager::class.java)
    private val addedProviders = mutableSetOf<String>()
    private val mockProviders = listOf(
        TestProviderSpec(
            name = LocationManager.GPS_PROVIDER,
            requiresNetwork = false,
            requiresSatellite = true,
            requiresCell = false,
            supportsAltitude = true,
            powerRequirement = android.location.Criteria.POWER_HIGH,
            accuracy = android.location.Criteria.ACCURACY_FINE,
        ),
        TestProviderSpec(
            name = LocationManager.NETWORK_PROVIDER,
            requiresNetwork = true,
            requiresSatellite = false,
            requiresCell = true,
            supportsAltitude = false,
            powerRequirement = android.location.Criteria.POWER_LOW,
            accuracy = android.location.Criteria.ACCURACY_FINE,
        ),
    )

    @Suppress("DEPRECATION")
    @SuppressLint("MissingPermission")
    fun start() {
        mockProviders.forEach { provider ->
            if (provider.name !in addedProviders) {
                try {
                    locationManager.addTestProvider(
                        provider.name,
                        provider.requiresNetwork,
                        provider.requiresSatellite,
                        provider.requiresCell,
                        false,
                        provider.supportsAltitude,
                        true,
                        true,
                        provider.powerRequirement,
                        provider.accuracy,
                    )
                } catch (_: IllegalArgumentException) {
                    // Provider may already exist from a previous service instance.
                }
                addedProviders += provider.name
            }
            locationManager.setTestProviderEnabled(provider.name, true)
        }
    }

    @SuppressLint("MissingPermission")
    fun pushLocation(
        point: RoutePoint,
        speedMetersPerSecond: Float,
        bearingDegrees: Float,
        accuracyMeters: Float = 5f,
    ) {
        start()
        val injectedPoint = CoordinateTransform.gcj02ToWgs84(point)
        mockProviders.forEach { provider ->
            val location = Location(provider.name).apply {
                latitude = injectedPoint.lat
                longitude = injectedPoint.lon
                if (provider.supportsAltitude) {
                    injectedPoint.altitude?.let { altitude = it }
                }
                accuracy = accuracyMeters
                speed = speedMetersPerSecond
                bearing = bearingDegrees
                time = System.currentTimeMillis()
                elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos()
            }
            locationManager.setTestProviderLocation(provider.name, location)
        }
    }

    fun stop() {
        addedProviders.toList().forEach { provider ->
            try {
                locationManager.removeTestProvider(provider)
            } catch (_: IllegalArgumentException) {
                // Already removed by the system or another service lifecycle.
            }
        }
        addedProviders.clear()
    }

    private data class TestProviderSpec(
        val name: String,
        val requiresNetwork: Boolean,
        val requiresSatellite: Boolean,
        val requiresCell: Boolean,
        val supportsAltitude: Boolean,
        val powerRequirement: Int,
        val accuracy: Int,
    )
}
