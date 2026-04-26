package com.aumi.app.streaming

/**
 * JNI Bridge to the C++/Oboe audio engine.
 */
object AudioBridge {
    
    init {
        // Disabled for diagnostics to find the startup crash
        /*
        try {
            System.loadLibrary("aumi_native")
        } catch (e: Throwable) {
            e.printStackTrace()
        }
        */
    }

    /**
     * Starts the native Oboe capture/playback engine.
     * Uses VoiceCommunication preset for hardware AEC.
     */
    external fun startNative()

    /**
     * Stops the native audio engine.
     */
    external fun stopNative()
    
    // Callbacks from C++ would be added here
}
