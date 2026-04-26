package com.aumi.app

import android.content.Intent
import android.os.Bundle
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class CrashActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val error = intent.getStringExtra("error") ?: "Unknown Ghost-Kill"
        
        val tv = TextView(this).apply {
            setPadding(64, 64, 64, 64)
            textSize = 16f
            text = "⚠️ Aumi Debug Report (Android 16)\n\n$error"
        }
        setContentView(tv)
    }
}
