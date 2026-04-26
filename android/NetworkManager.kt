package com.aumi.app

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject

class NetworkManager private constructor() {
    companion object {
        val shared = NetworkManager()
    }

    private var webSocket: WebSocket? = null
    private val client = OkHttpClient()
    private var nsdManager: NsdManager? = null
    var targetDeviceId: String = "macbook_pro" // Set after pairing

    fun initialize(context: Context) {
        startLocalDiscovery(context)
        connectToRelay()
    }

    private fun startLocalDiscovery(context: Context) {
        nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        
        val serviceInfo = NsdServiceInfo().apply {
            serviceName = "AumiPhone_${android.os.Build.MODEL}"
            serviceType = "_aumi._tcp"
            port = 8888 // Fixed port for LAN
        }

        nsdManager?.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(serviceInfo: NsdServiceInfo) {
                // Registered!
            }
            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
            override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) {}
            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
        })
    }

    private fun connectToRelay() {
        val request = Request.Builder().url("ws://your-relay-server:8080").build()
        webSocket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: okhttp3.Response) {
                val register = JSONObject().apply {
                    put("type", "REGISTER")
                    put("deviceId", "android_phone")
                }
                webSocket.send(register.toString())
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                handleIncomingMessage(text)
            }
        })
    }

    private fun handleIncomingMessage(text: String) {
        try {
            val json = JSONObject(text)
            when (json.optString("type")) {
                "CALL_ANSWER"  -> com.aumi.app.services.AumiInCallService.answerFromMac()
                "CALL_DECLINE" -> com.aumi.app.services.AumiInCallService.declineFromMac()
                "SMS_SEND" -> {
                    val recipient = json.optString("recipient")
                    val body = json.optString("body")
                    if (recipient.isNotEmpty() && body.isNotEmpty()) {
                        com.aumi.app.services.AumiSmsHandler().sendSMS(recipient, body)
                    }
                }
                else -> {} // Future commands
            }
        } catch (e: Exception) {
            android.util.Log.e("AumiNetwork", "Failed to parse incoming message", e)
        }
    }

    fun sendMessage(data: Map<String, Any>) {
        val json = JSONObject(data + mapOf("targetId" to targetDeviceId)).toString()
        webSocket?.send(json)
        // Also send via LAN TCP socket if connected
    }

    fun sendRawVideo(data: ByteArray, pts: Long) {
        // For video we send over a raw TCP socket (not WebSocket) to avoid framing overhead.
        // The LAN TCP socket implementation goes here.
        // Over relay we base64-encode as a fallback.
        val payload = mapOf(
            "type" to "SCREEN_STREAM_DATA",
            "pts" to pts,
            "data" to android.util.Base64.encodeToString(data, android.util.Base64.NO_WRAP),
            "targetId" to targetDeviceId
        )
        val json = JSONObject(payload).toString()
        webSocket?.send(json)
    }
}
