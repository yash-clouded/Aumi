package com.aumi.app.pairing

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.MultiFormatWriter
import org.json.JSONObject

object QRCodeUtil {

    /**
     * Generates a QR code bitmap for pairing.
     * The QR encodes: aumi://pair?id=<deviceId>&pubkey=<base64>&ip=<localIp>&port=<port>
     */
    fun generatePairingQR(
        deviceId: String,
        publicKeyBase64: String,
        localIp: String,
        port: Int,
        size: Int = 512
    ): Bitmap {
        val content = "aumi://pair?id=$deviceId&pubkey=$publicKeyBase64&ip=$localIp&port=$port"

        val hints = mapOf<EncodeHintType, Any>(
            EncodeHintType.MARGIN to 1,
            EncodeHintType.CHARACTER_SET to "UTF-8"
        )
        val matrix = MultiFormatWriter().encode(content, BarcodeFormat.QR_CODE, size, size, hints)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.RGB_565)
        for (x in 0 until size) {
            for (y in 0 until size) {
                bitmap.setPixel(x, y, if (matrix[x, y]) Color.BLACK else Color.WHITE)
            }
        }
        return bitmap
    }

    /**
     * Parses a scanned QR string into a [PairingManager.PairingPayload].
     * Returns null if the QR is not an Aumi pairing code.
     */
    fun parsePairingQR(raw: String): PairingManager.PairingPayload? {
        return try {
            if (!raw.startsWith("aumi://pair?")) return null
            val params = raw.removePrefix("aumi://pair?").split("&")
                .associate { param ->
                    val (k, v) = param.split("=", limit = 2)
                    k to v
                }
            PairingManager.PairingPayload(
                deviceId = params["id"] ?: return null,
                publicKeyBase64 = params["pubkey"] ?: return null,
                ip = params["ip"] ?: return null,
                port = params["port"]?.toIntOrNull() ?: return null
            )
        } catch (e: Exception) {
            null
        }
    }
}

/**
 * Camera-based QR scanner using CameraX + ML Kit.
 * Bind to a LifecycleOwner (Activity/Fragment) and pass in a PreviewView.
 */
class QRCodeScanner(private val context: Context) {

    private val options = BarcodeScannerOptions.Builder()
        .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
        .build()
    private val scanner = BarcodeScanning.getClient(options)

    fun startScanning(
        lifecycleOwner: LifecycleOwner,
        surfaceProvider: Preview.SurfaceProvider,
        onResult: (PairingManager.PairingPayload) -> Unit
    ) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()

            val preview = Preview.Builder().build().also {
                it.setSurfaceProvider(surfaceProvider)
            }

            val imageAnalysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()

            imageAnalysis.setAnalyzer(ContextCompat.getMainExecutor(context)) { imageProxy: ImageProxy ->
                val mediaImage = imageProxy.image ?: run { imageProxy.close(); return@setAnalyzer }
                val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
                scanner.process(image)
                    .addOnSuccessListener { barcodes ->
                        barcodes.firstNotNullOfOrNull { it.rawValue }?.let { raw ->
                            QRCodeUtil.parsePairingQR(raw)?.let { payload ->
                                onResult(payload)
                                cameraProvider.unbindAll()
                            }
                        }
                    }
                    .addOnCompleteListener { imageProxy.close() }
            }

            cameraProvider.bindToLifecycle(
                lifecycleOwner,
                CameraSelector.DEFAULT_BACK_CAMERA,
                preview,
                imageAnalysis
            )
        }, ContextCompat.getMainExecutor(context))
    }
}
