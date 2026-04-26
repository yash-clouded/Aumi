package com.aumi.app

import android.app.Application
import android.content.Intent
import com.aumi.app.crypto.AumiKeyStore

class AumiApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            val intent = Intent(this, CrashActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                putExtra("error", throwable.stackTraceToString())
            }
            startActivity(intent)
            System.exit(1)
        }

        try {
            AumiKeyStore.init(this)
        } catch (e: Throwable) {
            // Log and continue - don't crash the whole app
            e.printStackTrace()
        }
    }
}
