package com.aumi.app.media

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.view.Surface
import com.aumi.app.NetworkManager
import java.nio.ByteBuffer

class AumiVideoEncoder(private val width: Int, private val height: Int) {
    private var encoder: MediaCodec? = null
    var inputSurface: Surface? = null

    fun start() {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height)
        format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
        format.setInteger(MediaFormat.KEY_BIT_RATE, 2000000) // 2 Mbps
        format.setInteger(MediaFormat.KEY_FRAME_RATE, 60)
        format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1) // 1 second between I-frames

        encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        encoder?.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        inputSurface = encoder?.createInputSurface()

        encoder?.setCallback(object : MediaCodec.Callback() {
            override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {}

            override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
                val outputBuffer = codec.getOutputBuffer(index) ?: return
                val data = ByteArray(info.size)
                outputBuffer.get(data)
                
                // Send H.264 NAL units over TCP
                sendEncodedData(data, info.presentationTimeUs)
                
                codec.releaseOutputBuffer(index, false)
            }

            override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {}
            override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {}
        })

        encoder?.start()
    }

    private fun sendEncodedData(data: ByteArray, pts: Long) {
        // We use the direct TCP path for video to minimize overhead
        // This would call into our NetworkManager's raw socket
        NetworkManager.shared.sendRawVideo(data, pts)
    }

    fun stop() {
        encoder?.stop()
        encoder?.release()
        encoder = null
    }
}
