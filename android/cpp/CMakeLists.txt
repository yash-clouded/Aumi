cmake_minimum_required(VERSION 3.18.1)
project("aumi_native")

# Set the path to the Oboe library (cloned into android/cpp/oboe)
set (OBOE_DIR oboe)
add_subdirectory(${OBOE_DIR} ./oboe)

add_library(aumi_native SHARED
        audio_engine.cpp
        opus_codec.cpp
        jni_bridge.cpp
)

# Find liblog for Android logging
find_library(log-lib log)

# Find libopus (should be compiled or included as prebuilt)
# For simplicity in this implementation, we'll assume it's available or we'll stub the calls
# A real implementation would use a prebuilt .so or compile from source.

target_include_directories(aumi_native PRIVATE
        ${OBOE_DIR}/include
        ./include/opus
)

target_link_libraries(aumi_native
        oboe
        ${log-lib}
        # opus
)
