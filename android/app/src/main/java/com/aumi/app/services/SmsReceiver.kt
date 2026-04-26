package com.aumi.app.services

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.ContactsContract
import android.provider.Telephony
import com.aumi.app.service.AumiConnectionService
import org.json.JSONObject

/**
 * Catches incoming SMS via SMS_RECEIVED broadcast (fires before any notification).
 * This is more reliable than NotificationListenerService for SMS because:
 *  - It fires for ALL SMS apps (not just the default)
 *  - The data is structured (number, body, timestamp)
 *  - It works even if the user hasn't granted Notification Access
 */
class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        // Concatenate multi-part SMS bodies
        val sender    = messages[0].originatingAddress ?: return
        val body      = messages.joinToString("") { it.messageBody ?: "" }
        val timestamp = messages[0].timestampMillis
        
        // Look up contact name
        val contactName = lookupContactName(context, sender)

        val payload = JSONObject().apply {
            put("type",        "SMS")
            put("event",       "RECEIVED")
            put("number",      sender)
            put("contactName", contactName)
            put("body",        body)
            put("timestamp",   timestamp)
        }

        AumiConnectionService.instance?.sendControl(payload)
    }

    private fun lookupContactName(context: Context, number: String): String {
        val uri = android.net.Uri.withAppendedPath(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
            android.net.Uri.encode(number)
        )
        return context.contentResolver.query(
            uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
            null, null, null
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else number
        } ?: number
    }
}
