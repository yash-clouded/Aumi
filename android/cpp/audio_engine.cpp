#include <jni.h>
#include <string>
#include <oboe/Oboe.h>
#include <android/log.h>

#define TAG "AumiAudioEngine"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, TAG, __VA_ARGS__)

using namespace oboe;

class AumiAudioEngine : public AudioStreamCallback {
public:
    void start() {
        AudioStreamBuilder builder;
        builder.setDirection(Direction::Input)
               ->setPerformanceMode(PerformanceMode::LowLatency)
               ->setSharingMode(SharingMode::Exclusive)
               ->setFormat(AudioFormat::I16)
               ->setChannelCount(ChannelCount::Mono)
               ->setSampleRate(48000)
               ->setInputPreset(InputPreset::VoiceCommunication)
               ->setCallback(this)
               ->openStream(mStream);

        if (mStream) {
            mStream->requestStart();
            LOGD("Native Audio Engine Started ✅");
        }
    }

    void stop() {
        if (mStream) {
            mStream->stop();
            mStream->close();
            mStream.reset();
        }
    }

    DataCallbackResult onAudioReady(AudioStream *oboeStream, void *audioData, int32_t numFrames) override {
        // Here we would pass audioData to the Opus encoder
        // And then call back into Java to send via UDP
        return DataCallbackResult::Continue;
    }

private:
    ManagedStream mStream;
};

static AumiAudioEngine engine;

extern "C" JNIEXPORT void JNICALL
Java_com_aumi_app_streaming_AudioBridge_startNative(JNIEnv *env, jobject thiz) {
    engine.start();
}

extern "C" JNIEXPORT void JNICALL
Java_com_aumi_app_streaming_AudioBridge_stopNative(JNIEnv *env, jobject thiz) {
    engine.stop();
}
