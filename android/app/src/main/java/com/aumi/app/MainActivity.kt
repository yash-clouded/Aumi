package com.aumi.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import com.aumi.app.crypto.AumiKeyStore
import com.aumi.app.pairing.PairingManager
import com.aumi.app.pairing.QRCodeUtil
import com.aumi.app.service.AumiConnectionService

class MainActivity : AppCompatActivity() {

    private val projectionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            val intent = Intent(this, com.aumi.app.services.AumiMirroringService::class.java)
            intent.putExtra("resultCode", result.resultCode)
            intent.putExtra("resultData", result.data)
            startForegroundService(intent)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        AumiKeyStore.init(this)

        val btnPair = findViewById<Button>(R.id.btn_pair)
        val imgQr   = findViewById<ImageView>(R.id.img_qr)
        val txtStatus = findViewById<TextView>(R.id.txt_status)

        if (AumiKeyStore.isPaired()) {
            txtStatus.text = "Connected to paired Mac"
            startForegroundService(Intent(this, AumiConnectionService::class.java))
        }

        btnPair.setOnClickListener {
            // In a real app, we'd open the QR Scanner here.
            // For now, let's start the connection service.
            startForegroundService(Intent(this, AumiConnectionService::class.java))
        }

        findViewById<Button>(R.id.btn_mirror).setOnClickListener {
            val mpManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            projectionLauncher.launch(mpManager.createScreenCaptureIntent())
        }
    }
}
