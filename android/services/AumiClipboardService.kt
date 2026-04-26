package com.aumi.app.services

import android.app.Service
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.IBinder
import com.aumi.app.NetworkManager

class AumiClipboardService : Service() {

    private lateinit var clipboard: ClipboardManager
    private var lastSyncedText: String = ""

    override fun onCreate() {
        super.onCreate()
        clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.addPrimaryClipChangedListener {
            val clipData = clipboard.primaryClip
            if (clipData != null && clipData.itemCount > 0) {
                val text = clipData.getItemAt(0).text?.toString() ?: ""
                if (text.isNotEmpty() && text != lastSyncedText) {
                    lastSyncedText = text
                    syncToMac(text)
                }
            }
        }
    }

    private fun syncToMac(text: String) {
        val payload = mapOf(
            "type" to "CLIPBOARD_SYNC",
            "content" to text,
            "timestamp" to System.currentTimeMillis()
        )
        NetworkManager.shared.sendMessage(payload)
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
