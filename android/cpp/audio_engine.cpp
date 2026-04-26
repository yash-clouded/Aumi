#include <jni.h>
#include <android/log.h>

/**
 * Aumi Native Audio Engine (Stub)
 * 
 * Note: Oboe is currently disabled in the build script to allow for a quick APK build.
 * The production version will use Oboe for <10ms latency.
 * This stub ensures the JNI bridge remains functional.
 */

#define TAG "AumiAudioEngine"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, TAG, __VA_ARGS__)

class AumiAudioEngine {
public:
    void start() {
        LOGD("Native Audio Engine Started (Stub) ✅");
        // Integration with Oboe will happen here
    }

    void stop() {
        LOGD("Native Audio Engine Stopped (Stub) 🛑");
    }
};

static AumiAudioEngine engine;

// We move JNI functions to jni_bridge.cpp to keep it clean, 
// so we don't need them here once the bridge is updated.
