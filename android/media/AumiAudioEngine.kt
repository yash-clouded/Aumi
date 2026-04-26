package com.aumi.app.media

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import com.aumi.app.NetworkManager

class AumiAudioEngine {
    // Note: For near-zero latency, we would use Oboe (C++)
    // This is a high-level wrapper logic
    
    private var audioRecord: AudioRecord?
    private val sampleRate = 48000
    private val bufferSize = AudioRecord.getMinBufferSize(sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)

    fun start() {
        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize
        )

        audioRecord?.startRecording()
        
        Thread {
            val buffer = ShortArray(bufferSize)
            while (audioRecord?.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                val read = audioRecord?.read(buffer, 0, bufferSize) ?: 0
                if (read > 0) {
                    processAndSendAudio(buffer.sliceArray(0 until read))
                }
            }
        }.start()
    }

    private fun processAndSendAudio(data: ShortArray) {
        // 1. Encode with Opus (Native call)
        // 2. Send via UDP for lowest latency
        val payload = mapOf(
            "type" to "AUDIO_DATA",
            "data" to data // In reality, this is the Opus encoded bytes
        )
        // NetworkManager.shared.sendAudioPacket(payload)
    }

    fun stop() {
        audioRecord?.stop()
        audioRecord?.release()
    }
}
