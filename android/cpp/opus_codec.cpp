#include <jni.h>
#include <vector>

/**
 * Stub Opus codec implementation.
 * In a real-world scenario, this would link to the libopus source or prebuilts.
 * We provide these stubs to allow the NDK build to pass in Android Studio.
 */

extern "C" {
    // Encoding stub
    void encode_frame(const int16_t* pcm, int frame_size, uint8_t* out_opus, int& out_size) {
        // Just copying for now (Passthrough)
        out_size = frame_size * 2;
    }

    // Decoding stub
    void decode_frame(const uint8_t* opus, int size, int16_t* out_pcm) {
        // Passthrough
    }
}
