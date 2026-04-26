package com.aumi.app.focus

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioManager
import android.os.PowerManager
import com.aumi.app.service.AumiConnectionService
import org.json.JSONObject
import kotlin.math.abs

/**
 * Monitors Android device activity (screen, movement, audio) to determine focus.
 * Reports a "Focus State" to the Mac to enable smart auto-switching.
 */
class AumiFocusManager(private val context: Context) : SensorEventListener {

    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val powerManager  = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val audioManager  = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    
    private var lastX = 0f
    private var lastY = 0f
    private var lastZ = 0f
    private val motionThreshold = 1.0f  // Force threshold to detect "pickup"

    private var isScreenOn = false
    private var isInMotion = false
    private var hasAudioFocus = false

    fun start() {
        // 1. Monitor Motion
        val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        sensorManager.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_NORMAL)

        // 2. Initial States
        isScreenOn = powerManager.isInteractive
        
        // 3. Monitor Audio Focus
        audioManager.requestAudioFocus(null, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN) // Just a query
    }

    fun stop() {
        sensorManager.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type == Sensor.TYPE_ACCELEROMETER) {
            val x = event.values[0]
            val y = event.values[1]
            val z = event.values[2]

            val delta = abs(x - lastX) + abs(y - lastY) + abs(z - lastZ)
            val moving = delta > motionThreshold
            
            if (moving != isInMotion) {
                isInMotion = moving
                reportStatus()
            }

            lastX = x; lastY = y; lastZ = z
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    fun setScreenState(on: Boolean) {
        if (isScreenOn != on) {
            isScreenOn = on
            reportStatus()
        }
    }

    /**
     * Sends the current focus score to the Mac.
     * Logic: Screen ON + Motion = Highest priority for phone.
     */
    private fun reportStatus() {
        val payload = JSONObject().apply {
            put("type", "FOCUS_UPDATE")
            put("screenOn", isScreenOn)
            put("inMotion", isInMotion)
            put("audioActive", audioManager.isMusicActive)
            put("score", calculateScore())
        }
        AumiConnectionService.instance?.sendControl(payload)
    }

    private fun calculateScore(): Int {
        var score = 0
        if (isScreenOn) score += 50
        if (isInMotion) score += 30
        if (audioManager.isMusicActive) score += 20
        return score
    }
}
