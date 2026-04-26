package com.aumi.app.services

import android.telephony.SmsManager
import android.util.Log

class AumiSmsHandler {
    fun sendSMS(recipient: String, body: String) {
        try {
            val smsManager = SmsManager.getDefault()
            
            // Handle multi-part SMS if needed
            if (body.length > 160) {
                val parts = smsManager.divideMessage(body)
                smsManager.sendMultipartTextMessage(recipient, null, parts, null, null)
            } else {
                smsManager.sendTextMessage(recipient, null, body, null, null)
            }
            
            Log.d("AumiSMS", "SMS sent to $recipient")
        } catch (e: Exception) {
            Log.e("AumiSMS", "Failed to send SMS", e)
        }
    }
}
