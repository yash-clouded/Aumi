package com.aumi.app.ime

import android.content.ClipboardManager
import android.content.Context
import android.inputmethodservice.InputMethodService
import android.view.View
import com.aumi.app.service.AumiConnectionService
import org.json.JSONObject

/**
 * Aumi Input Method (IME).
 * On Android 10+, this is the only way to read the clipboard in the background.
 * This service acts as a "phantom" keyboard that monitors the clipboard while active.
 */
class AumiKeyboardService : InputMethodService() {

    private var clipboard: ClipboardManager? = null
    private var lastHashedContent: Int = 0

    override fun onCreate() {
        super.onCreate()
        clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        
        clipboard?.addPrimaryClipChangedListener {
            val clip = clipboard?.primaryClip ?: return@addPrimaryClipChangedListener
            if (clip.itemCount > 0) {
                val text = clip.getItemAt(0).text?.toString() ?: ""
                
                // Echo prevention: don't sync if this is what we just pasted from Mac
                if (text.hashCode() != lastHashedContent && text.isNotEmpty()) {
                    syncToMac(text)
                }
            }
        }
    }

    override fun onCreateInputView(): View {
        // Return a zero-height view or a minimal proxy UI
        return View(this)
    }

    private fun syncToMac(text: String) {
        val payload = JSONObject().apply {
            put("type", "CLIPBOARD")
            put("content", text)
        }
        AumiConnectionService.instance?.sendControl(payload)
    }

    /**
     * Called by AumiConnectionService when Mac sends a CLIPBOARD event.
     */
    fun onMacClipboardTarget(text: String) {
        lastHashedContent = text.hashCode()
        val clip = android.content.ClipData.newPlainText("Aumi Paste", text)
        clipboard?.setPrimaryClip(clip)
    }
}
