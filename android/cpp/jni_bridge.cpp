#include <jni.h>
#include <android/log.h>

extern "C" JNIEXPORT jint JNICALL
JNI_OnLoad(JavaVM* vm, void* reserved) {
    JNIEnv* env;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
        return JNI_ERR;
    }
    return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT void JNICALL
Java_com_aumi_app_streaming_AudioBridge_startNative(JNIEnv *env, jobject thiz) {
    __android_log_print(ANDROID_LOG_INFO, "AumiNative", "Starting native audio engine");
}

extern "C" JNIEXPORT void JNICALL
Java_com_aumi_app_streaming_AudioBridge_stopNative(JNIEnv *env, jobject thiz) {
    __android_log_print(ANDROID_LOG_INFO, "AumiNative", "Stopping native audio engine");
}
