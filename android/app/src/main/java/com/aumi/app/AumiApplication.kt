package com.aumi.app

import android.app.Application
import com.aumi.app.crypto.AumiKeyStore

class AumiApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Initialize secure storage globally
        AumiKeyStore.init(this)
    }
}
