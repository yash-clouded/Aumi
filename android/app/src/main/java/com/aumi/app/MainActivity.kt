package com.aumi.app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.aumi.app.crypto.AumiKeyStore
import com.aumi.app.pairing.QRCodeScanner
import com.aumi.app.service.AumiConnectionService

class MainActivity : AppCompatActivity() {

    private lateinit var qrScanner: QRCodeScanner

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val allGranted = permissions.entries.all { it.value }
        if (allGranted) {
            setupApp()
        } else {
            Toast.makeText(this, "Aumi needs permissions to mirror and sync.", Toast.LENGTH_LONG).show()
        }
    }

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

        qrScanner = QRCodeScanner(this)
        checkPermissionsAndStart()
    }

    private fun checkPermissionsAndStart() {
        val permissions = mutableListOf(
            Manifest.permission.CAMERA,
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_CONTACTS,
            Manifest.permission.RECEIVE_SMS,
            Manifest.permission.SEND_SMS,
            Manifest.permission.READ_SMS
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        if (permissions.any { ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED }) {
            requestPermissionLauncher.launch(permissions.toTypedArray())
        } else {
            setupApp()
        }
    }

    private fun setupApp() {
        val btnPair = findViewById<Button>(R.id.btn_pair)
        val txtStatus = findViewById<TextView>(R.id.txt_status)

        if (AumiKeyStore.isPaired()) {
            txtStatus.text = "Connected to paired Mac"
            tryStartService()
        }

        btnPair.setOnClickListener {
            val previewView = findViewById<androidx.camera.view.PreviewView>(R.id.preview_view)
            previewView.visibility = android.view.View.VISIBLE
            
            qrScanner.startScanning(this, previewView.surfaceProvider) { payload ->
                runOnUiThread {
                    previewView.visibility = android.view.View.GONE
                    AumiKeyStore.savePeerId(payload.ip)
                    AumiKeyStore.saveSessionKey(payload.publicKeyBase64.toByteArray()) // In real app, perform DH exchange
                    txtStatus.text = "Paired with Mac at ${payload.ip}"
                    Toast.makeText(this, "Pairing Successful!", Toast.LENGTH_SHORT).show()
                    tryStartService()
                }
            }
        }

        findViewById<Button>(R.id.btn_mirror).setOnClickListener {
            val mpManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            projectionLauncher.launch(mpManager.createScreenCaptureIntent())
        }
    }

    private fun tryStartService() {
        try {
            val intent = Intent(this, AumiConnectionService::class.java)
            startForegroundService(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
