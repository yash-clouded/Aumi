package com.aumi.app.services

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.content.Intent
import android.app.RemoteInput
import com.aumi.app.service.AumiConnectionService
import org.json.JSONArray
import org.json.JSONObject

class AumiNotificationListener : NotificationListenerService() {

    // Cache notification actions keyed by sbn.key for Reply/Archive from Mac
    private val actionCache = mutableMapOf<String, android.app.Notification.Action>()

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val pkg = sbn.packageName
        if (pkg == "com.aumi.app") return

        // ── Incoming Call Detection (HIGH PRIORITY) ──────────────────────────
        // Check for CATEGORY_CALL first to ensure we never miss a call regardless of flags
        val isCallNotif = sbn.notification.category == android.app.Notification.CATEGORY_CALL || 
                        pkg in listOf(
                            "com.samsung.android.incallui",
                            "com.android.incallui",
                            "com.google.android.dialer",
                            "com.android.server.telecom"
                        )

        if (isCallNotif) {
            val extras = sbn.notification.extras
            val name   = extras.getString("android.title") ?: extras.getString("android.text") ?: "Unknown Caller"
            val number = extras.getString("android.text") ?: ""
            
            // Cache available actions for Answer/Handle
            sbn.notification.actions?.forEach { action ->
                actionCache["${sbn.key}:${action.title}"] = action
            }

            val payload = JSONObject().apply {
                put("type",   "CALL_INCOMING")
                put("name",   name)
                put("number", number)
                put("id",     sbn.key)
            }
            AumiConnectionService.instance?.sendControl(payload)
            return
        }

        // ── Filter summaries and other noise for standard notifications ──────
        if (sbn.notification.flags and android.app.Notification.FLAG_GROUP_SUMMARY != 0) return

        // ── Gmail Notifications ───────────────────────────────────────────────
        if (pkg != "com.google.android.gm") return

        val extras = sbn.notification.extras
        val title  = extras.getString("android.title") ?: return
        val text   = extras.getCharSequence("android.text")?.toString() ?: ""

        // Extract available actions (Reply, Archive)
        val actions = sbn.notification.actions ?: emptyArray()
        val actionNames = JSONArray()
        actions.forEach { action ->
            actionNames.put(action.title.toString())
            // Cache for later use when Mac sends NOTIFICATION_ACTION
            actionCache["${sbn.key}:${action.title}"] = action
        }

        val payload = JSONObject().apply {
            put("type",      "NOTIFICATION")
            put("event",     "POSTED")
            put("key",       sbn.key)
            put("appName",   "Gmail")
            put("title",     title)
            put("text",      text)
            put("timestamp", sbn.postTime)
            put("actions",   actionNames)
        }

        AumiConnectionService.instance?.sendControl(payload)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        val pkg = sbn.packageName
        // Clean up action cache
        actionCache.keys.filter { it.startsWith(sbn.key) }.forEach { actionCache.remove(it) }

        // If a call notification was dismissed, tell Mac the call ended
        val isCallNotif = pkg in listOf(
            "com.samsung.android.incallui",
            "com.android.incallui",
            "com.google.android.dialer",
            "com.android.server.telecom"
        ) || sbn.notification.category == android.app.Notification.CATEGORY_CALL

        if (isCallNotif) {
            val payload = JSONObject().apply {
                put("type", "CALL_DISCONNECTED")
                put("id",   sbn.key)
            }
            AumiConnectionService.instance?.sendControl(payload)
            return
        }

        val payload = JSONObject().apply {
            put("type",  "NOTIFICATION")
            put("event", "REMOVED")
            put("key",   sbn.key)
        }
        AumiConnectionService.instance?.sendControl(payload)
    }

    /**
     * Called by AumiConnectionService when Mac sends NOTIFICATION_ACTION.
     * Finds the cached action and fires it — Gmail sends the reply or archives the email.
     */
    fun handleCallAction(callId: String, type: String) {
        android.util.Log.d("AumiNotif", "Remote action requested: $type")
        val audioManager = getSystemService(android.content.Context.AUDIO_SERVICE) as android.media.AudioManager
        
        if (type == "CALL_ANSWER") {
            // Simulate Bluetooth Headset "Answer" button press
            val downEvent = android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_HEADSETHOOK)
            audioManager.dispatchMediaKeyEvent(downEvent)
            val upEvent = android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, android.view.KeyEvent.KEYCODE_HEADSETHOOK)
            audioManager.dispatchMediaKeyEvent(upEvent)
            android.util.Log.d("AumiNotif", "Sent KEYCODE_HEADSETHOOK ✅")
        } else {
            // For Decline, we still use the notification action as it's more reliable for hanging up
            val prefix = "$callId:"
            val match = actionCache.keys.firstOrNull { key ->
                key.startsWith(prefix) && listOf("Decline", "Reject", "Hang up", "End").any { key.contains(it, ignoreCase = true) }
            }
            match?.let { 
                try {
                    actionCache[it]?.actionIntent?.send()
                    android.util.Log.d("AumiNotif", "Sent Decline Intent ✅")
                } catch (e: Exception) { e.printStackTrace() }
            }
        }
    }

    companion object {
        var instance: AumiNotificationListener? = null
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }
}
