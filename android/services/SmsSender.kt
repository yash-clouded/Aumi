package com.aumi.app.services

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.SmsManager
import com.aumi.app.service.AumiConnectionService
import org.json.JSONObject

class SmsSender(private val context: Context) {

    private val SENT_ACTION      = "com.aumi.SMS_SENT"
    private val DELIVERED_ACTION = "com.aumi.SMS_DELIVERED"

    fun sendSMS(recipient: String, body: String) {
        val smsManager = SmsManager.getDefault()

        val sentPI = PendingIntent.getBroadcast(
            context, 0,
            Intent(SENT_ACTION).putExtra("recipient", recipient),
            PendingIntent.FLAG_IMMUTABLE
        )
        val deliveredPI = PendingIntent.getBroadcast(
            context, 0,
            Intent(DELIVERED_ACTION).putExtra("recipient", recipient),
            PendingIntent.FLAG_IMMUTABLE
        )

        if (body.length > 160) {
            val parts = smsManager.divideMessage(body)
            val sentList      = ArrayList((1..parts.size).map { sentPI })
            val deliveredList = ArrayList((1..parts.size).map { deliveredPI })
            smsManager.sendMultipartTextMessage(recipient, null, parts, sentList, deliveredList)
        } else {
            smsManager.sendTextMessage(recipient, null, body, sentPI, deliveredPI)
        }
    }

    inner class SmsStatusReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val recipient = intent.getStringExtra("recipient") ?: ""
            when (intent.action) {
                SENT_ACTION -> {
                    val status = if (resultCode == android.app.Activity.RESULT_OK) "SENT" else "FAILED"
                    AumiConnectionService.instance?.sendControl(
                        JSONObject().put("type", "SMS").put("event", status).put("recipient", recipient)
                    )
                }
                DELIVERED_ACTION -> {
                    AumiConnectionService.instance?.sendControl(
                        JSONObject().put("type", "SMS").put("event", "DELIVERED").put("recipient", recipient)
                    )
                }
            }
        }
    }
}
