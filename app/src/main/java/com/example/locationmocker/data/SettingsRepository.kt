package com.example.locationmocker.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.example.locationmocker.domain.model.PlaybackMode
import com.example.locationmocker.domain.model.RoutePoint
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "simulation_settings")

data class SavedSettings(
    val speedKmh: Float = 5f,
    val playbackMode: PlaybackMode = PlaybackMode.Once,
    val points: List<RoutePoint> = emptyList(),
)

class SettingsRepository(private val context: Context) {
    private val speedKey = floatPreferencesKey("speed_kmh")
    private val playbackModeKey = stringPreferencesKey("playback_mode")
    private val routePointsKey = stringPreferencesKey("route_points")

    val settings: Flow<SavedSettings> = context.dataStore.data.map { preferences ->
        SavedSettings(
            speedKmh = preferences[speedKey]?.coerceIn(5f, 120f) ?: 5f,
            playbackMode = preferences[playbackModeKey]?.let { raw ->
                PlaybackMode.entries.firstOrNull { it.name == raw }
            } ?: PlaybackMode.Once,
            points = preferences[routePointsKey]?.let(::decodePoints).orEmpty(),
        )
    }

    suspend fun saveSpeed(speedKmh: Float) {
        context.dataStore.edit { it[speedKey] = speedKmh.coerceIn(5f, 120f) }
    }

    suspend fun savePlaybackMode(mode: PlaybackMode) {
        context.dataStore.edit { it[playbackModeKey] = mode.name }
    }

    suspend fun savePoints(points: List<RoutePoint>) {
        context.dataStore.edit { it[routePointsKey] = encodePoints(points) }
    }

    private fun encodePoints(points: List<RoutePoint>): String = points.joinToString(";") { point ->
        listOfNotNull(
            point.lat.toString(),
            point.lon.toString(),
            point.altitude?.toString(),
        ).joinToString(",")
    }

    private fun decodePoints(raw: String): List<RoutePoint> {
        if (raw.isBlank()) return emptyList()
        return raw.split(";").mapNotNull { encoded ->
            val parts = encoded.split(",")
            val lat = parts.getOrNull(0)?.toDoubleOrNull()
            val lon = parts.getOrNull(1)?.toDoubleOrNull()
            if (lat == null || lon == null) {
                null
            } else {
                RoutePoint(lat = lat, lon = lon, altitude = parts.getOrNull(2)?.toDoubleOrNull())
            }
        }
    }
}
