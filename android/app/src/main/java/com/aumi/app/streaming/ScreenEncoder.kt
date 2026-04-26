package com.aumi.app.streaming

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.view.Surface
import com.aumi.app.service.AumiConnectionService
import java.nio.ByteBuffer

/**
 * High-performance H.264 screen encoder using MediaCodec hardware acceleration.
 * Configured for real-time low latency (Baseline profile, no B-frames, CBR).
 */
class ScreenEncoder(private val width: Int, private val height: Int) {
    private var codec: MediaCodec? = null
    var inputSurface: Surface? = null
    private var isRunning = false

    fun start() {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height)
        
        // Low-latency configuration:
        // 1. Baseline profile (no B-frames = zero reordering delay)
        format.setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
        format.setInteger(MediaFormat.KEY_LEVEL, MediaCodecInfo.CodecProfileLevel.AVCLevel4)
        
        // 2. Constant Bitrate (CBR) for predictable network performance
        format.setInteger(MediaFormat.KEY_BITRATE_MODE, MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR)
        format.setInteger(MediaFormat.KEY_BIT_RATE, 4_000_000) // 4 Mbps default
        
        // 3. High FPS
        format.setInteger(MediaFormat.KEY_FRAME_RATE, 60)
        format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1) // 1 second for fast recovery
        
        // 4. Zero-latency color format (Surface input)
        format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)

        codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        codec?.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        inputSurface = codec?.createInputSurface()

        codec?.setCallback(object : MediaCodec.Callback() {
            override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {}

            override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
                val buffer = codec.getOutputBuffer(index) ?: return
                val data = ByteArray(info.size)
                buffer.get(data)

                // Binary Frame Flags: 0x01 = Keyframe, 0x02 = Config (SPS/PPS)
                var flags: Byte = 0
                if (info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0) flags = flags or 0x01
                if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) flags = flags or 0x02

                // Send over TCP via ConnectionService
                AumiConnectionService.instance?.sendVideo(data, info.presentationTimeUs, flags)
                
                codec.releaseOutputBuffer(index, false)
            }

            override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {}
            override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {}
        })

        codec?.start()
        isRunning = true
    }

    fun stop() {
        isRunning = false
        codec?.stop()
        codec?.release()
        codec = null
        inputSurface = null
    }
}

private infix fun Byte.or(other: Int): Byte = (this.toInt() or other).toByte()
