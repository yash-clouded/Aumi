package com.aumi.app.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.util.DisplayMetrics
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import com.aumi.app.streaming.ScreenEncoder

/**
 * Handles real-time screen capture and hardware H.264 encoding.
 * Runs as a foreground service of type 'mediaProjection'.
 */
class AumiMirroringService : Service() {

    companion object {
        const val CHANNEL_ID = "aumi_mirroring"
        const val NOTIF_ID   = 101
    }

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var encoder: ScreenEncoder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val resultCode = intent?.getIntExtra("resultCode", -1) ?: -1
        val resultData = intent?.getParcelableExtra<Intent>("resultData")

        if (resultCode != -1 && resultData != null) {
            // Android 14+ requirement: Start foreground BEFORE acquiring MediaProjection
            startForeground(NOTIF_ID, createNotification())
            
            val mpManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            mediaProjection = mpManager.getMediaProjection(resultCode, resultData)
            
            setupMirroring()
        } else {
            stopSelf()
        }

        return START_NOT_STICKY
    }

    private fun setupMirroring() {
        val metrics = DisplayMetrics()
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        wm.defaultDisplay.getRealMetrics(metrics)

        // Initialize hardware encoder
        encoder = ScreenEncoder(metrics.widthPixels, metrics.heightPixels)
        encoder?.start()

        // Create virtual display outputting to encoder surface
        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "AumiMirror",
            metrics.widthPixels, metrics.heightPixels, metrics.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            encoder?.inputSurface,
            null, null
        )

        mediaProjection?.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                stopSelf()
            }
        }, null)
    }

    override fun onDestroy() {
        super.onDestroy()
        virtualDisplay?.release()
        encoder?.stop()
        mediaProjection?.stop()
        virtualDisplay = null
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Aumi Mirroring")
            .setContentText("Phone screen shared with Mac")
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Aumi Mirroring",
                NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
