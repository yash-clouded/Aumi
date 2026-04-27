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
        if (sbn.notification.flags and android.app.Notification.FLAG_GROUP_SUMMARY != 0) return

        // ── Incoming Call Detection ───────────────────────────────────────────
        // Works for Samsung Phone, AOSP Dialer, and most OEM dialers
        val isCallNotif = pkg in listOf(
            "com.samsung.android.incallui",
            "com.android.incallui",
            "com.google.android.dialer",
            "com.android.server.telecom"
        ) || sbn.notification.category == android.app.Notification.CATEGORY_CALL

        if (isCallNotif) {
            val extras = sbn.notification.extras
            val name   = extras.getString("android.title") ?: extras.getString("android.text") ?: "Unknown Caller"
            val number = extras.getString("android.text") ?: ""
            val payload = JSONObject().apply {
                put("type",   "CALL_INCOMING")
                put("name",   name)
                put("number", number)
                put("id",     sbn.key)
            }
            AumiConnectionService.instance?.sendControl(payload)
            return
        }

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
    fun performAction(key: String, actionName: String, replyText: String? = null) {
        val cacheKey = "$key:$actionName"
        val action   = actionCache[cacheKey] ?: return

        val intent = action.actionIntent
        if (replyText != null) {
            // Fill RemoteInput for Reply
            val remoteInputs = action.remoteInputs ?: return
            val resultData   = Intent()
            val bundle       = android.os.Bundle()
            remoteInputs.forEach { ri ->
                bundle.putCharSequence(ri.resultKey, replyText)
            }
            RemoteInput.addResultsToIntent(remoteInputs, resultData, bundle)
            intent.send(applicationContext, 0, resultData)
        } else {
            intent.send()
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
