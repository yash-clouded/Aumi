package com.aumi.app.services

import android.telecom.Call
import android.telecom.InCallService
import android.util.Log
import com.aumi.app.service.AumiConnectionService
import org.json.JSONObject

class AumiInCallService : InCallService() {

    // Track the active call so Mac commands can control it
    private var activeCall: Call? = null

    companion object {
        // Called by NetworkManager when a CALL_ANSWER or CALL_DECLINE arrives from Mac
        var instance: AumiInCallService? = null

        fun answerFromMac() {
            instance?.activeCall?.answer(/* videoState= */ 0)
        }

        fun declineFromMac() {
            instance?.activeCall?.reject(/* rejectWithMessage= */ false, null)
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        activeCall = call
        Log.d("Aumi", "Call added: ${call.details.handle}")

        call.registerCallback(object : Call.Callback() {
            override fun onStateChanged(call: Call, state: Int) {
                when (state) {
                    Call.STATE_RINGING -> notifyMacIncoming(call)
                    Call.STATE_DISCONNECTED -> notifyMacDisconnected(call)
                }
            }
        })

        if (call.state == Call.STATE_RINGING) {
            notifyMacIncoming(call)
        }
    }

    private fun notifyMacIncoming(call: Call) {
        val number = call.details.handle.schemeSpecificPart
        val name = "Unknown Caller"
        val payload = JSONObject().apply {
            put("type", "CALL_INCOMING")
            put("number", number)
            put("name", name)
            put("id", call.hashCode().toString())
        }
        AumiConnectionService.instance?.sendControl(payload)
    }

    private fun notifyMacDisconnected(call: Call) {
        val payload = JSONObject().apply {
            put("type", "CALL_DISCONNECTED")
            put("id", call.hashCode().toString())
        }
        AumiConnectionService.instance?.sendControl(payload)
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        if (call == activeCall) activeCall = null
    }
}
