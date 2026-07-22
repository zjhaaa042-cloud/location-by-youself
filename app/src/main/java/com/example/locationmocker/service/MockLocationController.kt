package com.example.locationmocker.service

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.location.LocationManager
import android.location.provider.ProviderProperties
import android.os.Build
import android.os.SystemClock
import com.example.locationmocker.domain.geo.CoordinateTransform
import com.example.locationmocker.domain.model.RoutePoint
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationServices
import com.google.android.gms.tasks.Tasks
import java.util.concurrent.TimeUnit

class MockLocationController(context: Context) {
    private val locationManager = context.getSystemService(LocationManager::class.java)
    private val fusedLocationClient: FusedLocationProviderClient? =
        if (
            GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) ==
            ConnectionResult.SUCCESS
        ) {
            LocationServices.getFusedLocationProviderClient(context.applicationContext)
        } else {
            null
        }
    private val addedProviders = mutableSetOf<String>()
    private var fusedMockModeEnabled = false
    private var fusedMockModeUnavailable = false
    private val mockProviders = buildList {
        add(
            TestProviderSpec(
                name = LocationManager.GPS_PROVIDER,
                requiresNetwork = false,
                requiresSatellite = true,
                requiresCell = false,
                supportsAltitude = true,
                powerRequirement = ProviderProperties.POWER_USAGE_HIGH,
                accuracy = ProviderProperties.ACCURACY_FINE,
            ),
        )
        add(
            TestProviderSpec(
                name = LocationManager.NETWORK_PROVIDER,
                requiresNetwork = true,
                requiresSatellite = false,
                requiresCell = true,
                supportsAltitude = false,
                powerRequirement = ProviderProperties.POWER_USAGE_LOW,
                accuracy = ProviderProperties.ACCURACY_FINE,
            ),
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            add(
                TestProviderSpec(
                    name = LocationManager.FUSED_PROVIDER,
                    requiresNetwork = true,
                    requiresSatellite = true,
                    requiresCell = true,
                    supportsAltitude = true,
                    powerRequirement = ProviderProperties.POWER_USAGE_MEDIUM,
                    accuracy = ProviderProperties.ACCURACY_FINE,
                ),
            )
        }
    }

    @SuppressLint("MissingPermission")
    fun start() {
        mockProviders.forEach { provider ->
            if (provider.name !in addedProviders) {
                try {
                    addTestProvider(provider)
                } catch (_: IllegalArgumentException) {
                    // Provider may already exist from a previous service instance.
                }
                addedProviders += provider.name
            }
            locationManager.setTestProviderEnabled(provider.name, true)
        }
        enableFusedMockMode()
    }

    @Suppress("DEPRECATION")
    private fun addTestProvider(provider: TestProviderSpec) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val properties = ProviderProperties.Builder()
                .setHasNetworkRequirement(provider.requiresNetwork)
                .setHasSatelliteRequirement(provider.requiresSatellite)
                .setHasCellRequirement(provider.requiresCell)
                .setHasMonetaryCost(false)
                .setHasAltitudeSupport(provider.supportsAltitude)
                .setHasSpeedSupport(true)
                .setHasBearingSupport(true)
                .setPowerUsage(provider.powerRequirement)
                .setAccuracy(provider.accuracy)
                .build()
            locationManager.addTestProvider(provider.name, properties)
        } else {
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
            val location = createLocation(
                providerName = provider.name,
                point = injectedPoint,
                supportsAltitude = provider.supportsAltitude,
                speedMetersPerSecond = speedMetersPerSecond,
                bearingDegrees = bearingDegrees,
                accuracyMeters = accuracyMeters,
            )
            locationManager.setTestProviderLocation(provider.name, location)
        }
        pushFusedLocation(
            createLocation(
                providerName = FUSED_PROVIDER_NAME,
                point = injectedPoint,
                supportsAltitude = true,
                speedMetersPerSecond = speedMetersPerSecond,
                bearingDegrees = bearingDegrees,
                accuracyMeters = accuracyMeters,
            ),
        )
    }

    @SuppressLint("MissingPermission")
    fun stop() {
        try {
            fusedLocationClient?.takeIf { fusedMockModeEnabled }
                ?.setMockMode(false)
        } catch (_: SecurityException) {
            // The app may have been deselected as the mock location app before stopping.
        }
        fusedMockModeEnabled = false
        addedProviders.toList().forEach { provider ->
            try {
                locationManager.removeTestProvider(provider)
            } catch (_: IllegalArgumentException) {
                // Already removed by the system or another service lifecycle.
            }
        }
        addedProviders.clear()
    }

    @SuppressLint("MissingPermission")
    private fun enableFusedMockMode() {
        val client = fusedLocationClient ?: return
        if (fusedMockModeEnabled || fusedMockModeUnavailable) return
        try {
            Tasks.await(
                client.setMockMode(true),
                FUSED_OPERATION_TIMEOUT_SECONDS,
                TimeUnit.SECONDS,
            )
            fusedMockModeEnabled = true
        } catch (error: Exception) {
            if (error is InterruptedException) Thread.currentThread().interrupt()
            // Devices without a working Google Play location service keep using the platform
            // GPS/network/fused test providers configured above.
            fusedMockModeUnavailable = true
        }
    }

    @SuppressLint("MissingPermission")
    private fun pushFusedLocation(location: Location) {
        val client = fusedLocationClient ?: return
        if (!fusedMockModeEnabled) return
        try {
            Tasks.await(
                client.setMockLocation(location),
                FUSED_OPERATION_TIMEOUT_SECONDS,
                TimeUnit.SECONDS,
            )
        } catch (error: Exception) {
            if (error is InterruptedException) Thread.currentThread().interrupt()
            fusedMockModeEnabled = false
            fusedMockModeUnavailable = true
        }
    }

    private fun createLocation(
        providerName: String,
        point: RoutePoint,
        supportsAltitude: Boolean,
        speedMetersPerSecond: Float,
        bearingDegrees: Float,
        accuracyMeters: Float,
    ): Location = Location(providerName).apply {
        latitude = point.lat
        longitude = point.lon
        if (supportsAltitude) {
            point.altitude?.let { altitude = it }
        }
        accuracy = accuracyMeters
        speed = speedMetersPerSecond
        bearing = bearingDegrees
        time = System.currentTimeMillis()
        elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos()
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

    private companion object {
        private const val FUSED_PROVIDER_NAME = "fused"
        private const val FUSED_OPERATION_TIMEOUT_SECONDS = 3L
    }
}
