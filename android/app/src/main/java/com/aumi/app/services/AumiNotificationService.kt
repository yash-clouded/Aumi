package com.aumi.app.services

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.aumi.app.NetworkManager

class AumiNotificationService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val packageName = sbn.packageName
        val extras = sbn.notification.extras
        val title = extras.getString("android.title") ?: ""
        val text = extras.getCharSequence("android.text")?.toString() ?: ""

        Log.d("AumiNotif", "Notif from $packageName: $title - $text")

        // Filter for specific apps or general mirroring
        if (packageName.contains("gmail") || packageName.contains("mms") || packageName.contains("messaging")) {
            val type = if (packageName.contains("gmail")) "NOTIF_GMAIL" else "SMS_RECEIVED"
            
            val payload = mapOf(
                "type" to type,
                "title" to title,
                "body" to text,
                "package" to packageName,
                "timestamp" to System.currentTimeMillis()
            )
            
            NetworkManager.shared.sendMessage(payload)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        // Optional: Sync notification dismissal
    }
}
