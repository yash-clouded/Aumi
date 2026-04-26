package com.aumi.app.service

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import com.aumi.app.crypto.AESCipher
import com.aumi.app.crypto.AumiKeyStore
import kotlinx.coroutines.*
import org.json.JSONObject
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Socket

/**
 * The heart of Aumi on Android. Runs as a persistent foreground service.
 * Manages:
 *  - LAN TCP socket (control messages + H.264 video, port X)
 *  - LAN UDP socket (Opus audio, port X+1)
 *  - Relay WebSocket (fallback when off LAN)
 *  - Message dispatch to all subsystems
 *  - Heartbeat keepalive
 */
class AumiConnectionService : Service() {

    companion object {
        const val CHANNEL_ID = "aumi_connection"
        const val NOTIF_ID   = 1
        const val TCP_PORT   = 8765
        const val UDP_PORT   = 8766  // TCP + 1

        // Broadcast actions for inter-component communication
        const val ACTION_SEND_MESSAGE   = "com.aumi.SEND_MESSAGE"
        const val ACTION_SEND_RAW_VIDEO = "com.aumi.SEND_VIDEO"

        var instance: AumiConnectionService? = null
    }

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var tcpSocket: Socket? = null
    private var tcpOut: DataOutputStream? = null
    private var udpSocket: DatagramSocket? = null
    private var sessionKey: ByteArray? = null
    private var macIp: String? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var reconnectJob: Job? = null

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        instance = this
        try {
            sessionKey = AumiKeyStore.loadSessionKey()
        } catch (e: Exception) {
            e.printStackTrace()
            AumiKeyStore.clearPairing()
        }
        createNotificationChannel()
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIF_ID, 
                buildNotification("Connecting…"), 
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            )
        } else {
            startForeground(NOTIF_ID, buildNotification("Connecting…"))
        }

        macIp = intent?.getStringExtra("macIp") ?: AumiKeyStore.loadPeerId()
        macIp?.let { connectToMac(it) }

        return START_STICKY  // Restart if killed
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        serviceScope.cancel()
        wakeLock?.release()
        closeSockets()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Connection ────────────────────────────────────────────────────────────

    private fun connectToMac(ip: String) {
        reconnectJob?.cancel()
        reconnectJob = serviceScope.launch {
            var attempt = 0
            while (isActive) {
                try {
                    closeSockets()
                    tcpSocket = Socket(ip, TCP_PORT).also { it.tcpNoDelay = true }
                    tcpOut = DataOutputStream(tcpSocket!!.getOutputStream())
                    udpSocket = DatagramSocket(UDP_PORT)

                    updateNotification("Connected to Mac • LAN")
                    startHeartbeat()
                    listenTCP()
                    break  // Clean exit — no reconnect needed
                } catch (e: Exception) {
                    val delay = minOf(1000L * (1 shl attempt), 30000L)  // Exp. backoff, max 30s
                    updateNotification("Reconnecting in ${delay/1000}s…")
                    delay(delay)
                    attempt++
                }
            }
        }
    }

    // ── TCP Receive Loop ──────────────────────────────────────────────────────

    private fun CoroutineScope.listenTCP() = launch {
        try {
            val din = DataInputStream(tcpSocket!!.getInputStream())
            while (isActive) {
                val type   = din.readByte()
                val length = din.readInt()
                val iv     = ByteArray(12).also { din.readFully(it) }
                val body   = ByteArray(length).also { din.readFully(it) }

                sessionKey?.let { key ->
                    val payload = AESCipher.decrypt(key, iv + body)
                    dispatch(type, payload)
                }
            }
        } catch (e: Exception) {
            // Connection dropped — trigger reconnect
            macIp?.let { connectToMac(it) }
        }
    }

    // ── Message Dispatch ──────────────────────────────────────────────────────

    private fun dispatch(type: Byte, payload: ByteArray) {
        val json = runCatching { JSONObject(String(payload)) }.getOrNull() ?: return
        when (type) {
            0x01.toByte() -> handleControl(json)         // Control message
            0xF0.toByte() -> { /* video — not applicable on Android receive */ }
        }
    }

    private fun handleControl(json: JSONObject) {
        when (json.optString("type")) {
            "CALL_ANSWER"  -> com.aumi.app.services.AumiInCallService.answerFromMac()
            "CALL_DECLINE" -> com.aumi.app.services.AumiInCallService.declineFromMac()
            "SMS_SEND" -> {
                val to   = json.optString("recipient")
                val body = json.optString("body")
                if (to.isNotEmpty() && body.isNotEmpty()) {
                    com.aumi.app.services.AumiSmsHandler().sendSMS(to, body)
                }
            }
            "HEARTBEAT_ACK" -> { /* connection alive */ }
        }
    }

    // ── Sending ───────────────────────────────────────────────────────────────

    /**
     * Sends a control message (JSON) over the encrypted TCP channel.
     * Framing: [0x01][len(4B)][iv(12B)][encrypted body]
     */
    fun sendControl(json: JSONObject) {
        serviceScope.launch {
            val key = sessionKey ?: return@launch
            val payload   = AESCipher.encrypt(key, json.toString().toByteArray())
            val iv        = payload.sliceArray(0 until 12)
            val ciphertext = payload.sliceArray(12 until payload.size)
            synchronized(this@AumiConnectionService) {
                tcpOut?.apply {
                    writeByte(0x01)
                    writeInt(ciphertext.size)
                    write(iv)
                    write(ciphertext)
                    flush()
                }
            }
        }
    }

    /**
     * Sends raw H.264 NAL data over the TCP channel.
     * Framing: [0xF0][len(4B)][pts(8B)][flags(1B)][encrypted NAL data]
     */
    fun sendVideo(nalData: ByteArray, pts: Long, flags: Byte) {
        serviceScope.launch {
            val key = sessionKey ?: return@launch
            val encrypted = AESCipher.encrypt(key, nalData)
            synchronized(this@AumiConnectionService) {
                tcpOut?.apply {
                    writeByte(0xF0)
                    writeInt(encrypted.size)
                    writeLong(pts)
                    writeByte(flags.toInt())
                    write(encrypted)
                    flush()
                }
            }
        }
    }

    /**
     * Sends Opus audio frame over UDP (fire-and-forget, low latency).
     * Framing: [seq(2B)][iv(12B)][len(2B)][encrypted Opus frame]
     */
    private var udpSeq: Short = 0
    fun sendAudio(opusFrame: ByteArray) {
        serviceScope.launch {
            val key    = sessionKey ?: return@launch
            val socket = udpSocket ?: return@launch
            val ip     = macIp ?: return@launch
            val enc    = AESCipher.encrypt(key, opusFrame)
            val iv     = enc.sliceArray(0 until 12)
            val ct     = enc.sliceArray(12 until enc.size)
            val packet = ByteArray(2 + 12 + 2 + ct.size)
            packet[0] = (udpSeq.toInt() shr 8).toByte()
            packet[1] = udpSeq.toByte()
            iv.copyInto(packet, 2)
            packet[14] = (ct.size shr 8).toByte()
            packet[15] = ct.size.toByte()
            ct.copyInto(packet, 16)
            udpSeq++
            val datagram = DatagramPacket(packet, packet.size,
                java.net.InetAddress.getByName(ip), UDP_PORT)
            socket.send(datagram)
        }
    }

    // ── Heartbeat ─────────────────────────────────────────────────────────────

    private fun startHeartbeat() {
        serviceScope.launch {
            while (isActive) {
                delay(5000)
                sendControl(JSONObject().put("type", "HEARTBEAT"))
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Aumi::ConnectionWakeLock")
        wakeLock?.acquire(10 * 60 * 60 * 1000L)  // 10 hours max
    }

    private fun closeSockets() {
        runCatching { tcpSocket?.close() }
        runCatching { udpSocket?.close() }
        tcpSocket = null; tcpOut = null; udpSocket = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Aumi Connection",
                NotificationManager.IMPORTANCE_LOW
            ).apply { setShowBadge(false) }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(status: String): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Aumi")
            .setContentText(status)
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .setOngoing(true)
            .build()

    private fun updateNotification(status: String) {
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(NOTIF_ID, buildNotification(status))
    }
}
