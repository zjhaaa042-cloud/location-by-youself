package com.example.locationmocker.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.example.locationmocker.MainActivity
import com.example.locationmocker.R
import com.example.locationmocker.domain.model.PlaybackMode
import com.example.locationmocker.domain.model.RoutePoint
import com.example.locationmocker.domain.model.SimulationConfig
import com.example.locationmocker.domain.route.PlaybackCursor
import com.example.locationmocker.domain.route.RoutePlanner
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class MockLocationService : Service() {
    private val serviceJob = SupervisorJob()
    private val scope = CoroutineScope(serviceJob + Dispatchers.Default)
    private lateinit var mockController: MockLocationController
    private var runnerJob: Job? = null
    private var paused = false

    override fun onCreate() {
        super.onCreate()
        mockController = MockLocationController(this)
        ensureNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_FIXED -> startFixed(intent)
            ACTION_START_ROUTE -> startRoute(intent)
            ACTION_PAUSE -> {
                paused = true
                SimulationProgressBus.setPaused(true)
                updateNotification()
            }
            ACTION_RESUME -> {
                paused = false
                SimulationProgressBus.setPaused(false)
                updateNotification()
            }
            ACTION_STOP -> stopSimulation(clearProgress = true)
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        runnerJob?.cancel()
        serviceJob.cancel()
        mockController.stop()
        super.onDestroy()
    }

    private fun startFixed(intent: Intent) {
        val point = intent.readPoints().firstOrNull() ?: return
        paused = false
        SimulationProgressBus.update(
            SimulationProgress(
                point = point,
                speedMetersPerSecond = 0f,
                bearingDegrees = 0f,
                isRoute = false,
            ),
        )
        startForeground(NOTIFICATION_ID, buildNotification(paused = false))
        runnerJob?.cancel()
        runnerJob = scope.launch {
            while (isActive) {
                if (!paused) {
                    try {
                        mockController.pushLocation(
                            point = point,
                            speedMetersPerSecond = 0f,
                            bearingDegrees = 0f,
                        )
                        SimulationProgressBus.update(
                            SimulationProgress(
                                point = point,
                                speedMetersPerSecond = 0f,
                                bearingDegrees = 0f,
                                isRoute = false,
                            ),
                        )
                    } catch (error: RuntimeException) {
                        SimulationProgressBus.fail("模拟定位写入失败：${error.message ?: "请确认已选择模拟位置应用"}")
                        stopSimulation(clearProgress = false)
                        return@launch
                    }
                }
                delay(DEFAULT_INTERVAL_MS)
            }
        }
    }

    private fun startRoute(intent: Intent) {
        val points = intent.readPoints()
        if (points.isEmpty()) return
        val speedKmh = intent.getFloatExtra(EXTRA_SPEED_KMH, 5f).coerceIn(5f, 120f)
        val mode = intent.getStringExtra(EXTRA_PLAYBACK_MODE)?.let { raw ->
            PlaybackMode.entries.firstOrNull { it.name == raw }
        } ?: PlaybackMode.Once
        val intervalMs = intent.getLongExtra(EXTRA_UPDATE_INTERVAL_MS, DEFAULT_INTERVAL_MS)
        val config = SimulationConfig(points, speedKmh, mode, intervalMs)
        val samples = RoutePlanner().buildSamples(config)
        val cursor = PlaybackCursor(samples, mode)

        paused = false
        startForeground(NOTIFICATION_ID, buildNotification(paused = false))
        runnerJob?.cancel()
        runnerJob = scope.launch {
            while (isActive) {
                if (!paused) {
                    val sample = cursor.next()
                    if (sample == null) {
                        stopSimulation(clearProgress = true)
                        return@launch
                    }
                    try {
                        mockController.pushLocation(
                            point = sample.point,
                            speedMetersPerSecond = sample.speedMetersPerSecond,
                            bearingDegrees = sample.bearingDegrees,
                        )
                        SimulationProgressBus.update(
                            SimulationProgress(
                                point = sample.point,
                                speedMetersPerSecond = sample.speedMetersPerSecond,
                                bearingDegrees = sample.bearingDegrees,
                                isRoute = true,
                            ),
                        )
                    } catch (error: RuntimeException) {
                        SimulationProgressBus.fail("模拟定位写入失败：${error.message ?: "请确认已选择模拟位置应用"}")
                        stopSimulation(clearProgress = false)
                        return@launch
                    }
                }
                delay(intervalMs)
            }
        }
    }

    private fun stopSimulation(clearProgress: Boolean) {
        runnerJob?.cancel()
        runnerJob = null
        mockController.stop()
        if (clearProgress) {
            SimulationProgressBus.clear()
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun updateNotification() {
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification(paused = paused))
    }

    private fun buildNotification(paused: Boolean): Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val pauseAction = if (paused) ACTION_RESUME else ACTION_PAUSE
        val pauseTitle = if (paused) "继续" else "暂停"
        val pauseIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, MockLocationService::class.java).setAction(pauseAction),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stopIntent = PendingIntent.getService(
            this,
            2,
            Intent(this, MockLocationService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("定位模拟运行中")
            .setContentText("通过 Android 官方 Mock Location API 输出位置")
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(android.R.drawable.ic_media_pause, pauseTitle, pauseIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "停止", stopIntent)
            .build()
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.mock_service_channel),
            NotificationManager.IMPORTANCE_LOW,
        )
        manager.createNotificationChannel(channel)
    }

    private fun Intent.readPoints(): List<RoutePoint> {
        val lats = getDoubleArrayExtra(EXTRA_LATS) ?: DoubleArray(0)
        val lons = getDoubleArrayExtra(EXTRA_LONS) ?: DoubleArray(0)
        val pointCount = minOf(lats.size, lons.size)
        return List(pointCount) { index ->
            RoutePoint(lat = lats[index], lon = lons[index])
        }
    }

    companion object {
        private const val CHANNEL_ID = "mock_location"
        private const val NOTIFICATION_ID = 31
        private const val DEFAULT_INTERVAL_MS = 1_000L

        const val ACTION_START_FIXED = "com.example.locationmocker.START_FIXED"
        const val ACTION_START_ROUTE = "com.example.locationmocker.START_ROUTE"
        const val ACTION_PAUSE = "com.example.locationmocker.PAUSE"
        const val ACTION_RESUME = "com.example.locationmocker.RESUME"
        const val ACTION_STOP = "com.example.locationmocker.STOP"

        private const val EXTRA_LATS = "lats"
        private const val EXTRA_LONS = "lons"
        private const val EXTRA_SPEED_KMH = "speed_kmh"
        private const val EXTRA_PLAYBACK_MODE = "playback_mode"
        private const val EXTRA_UPDATE_INTERVAL_MS = "update_interval_ms"

        fun startFixedIntent(context: Context, point: RoutePoint): Intent =
            Intent(context, MockLocationService::class.java)
                .setAction(ACTION_START_FIXED)
                .putExtra(EXTRA_LATS, doubleArrayOf(point.lat))
                .putExtra(EXTRA_LONS, doubleArrayOf(point.lon))

        fun startRouteIntent(context: Context, config: SimulationConfig): Intent =
            Intent(context, MockLocationService::class.java)
                .setAction(ACTION_START_ROUTE)
                .putExtra(EXTRA_LATS, config.points.map { it.lat }.toDoubleArray())
                .putExtra(EXTRA_LONS, config.points.map { it.lon }.toDoubleArray())
                .putExtra(EXTRA_SPEED_KMH, config.speedKmh)
                .putExtra(EXTRA_PLAYBACK_MODE, config.mode.name)
                .putExtra(EXTRA_UPDATE_INTERVAL_MS, config.updateIntervalMs)

        fun stopIntent(context: Context): Intent =
            Intent(context, MockLocationService::class.java).setAction(ACTION_STOP)
    }
}
