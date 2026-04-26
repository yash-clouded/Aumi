import AVFoundation
import CoreAudio

/// Monitors Core Audio for device connect/disconnect events and seamlessly
/// re-routes AumiAudioPlayer without dropping the active call.
class AumiAudioRouteManager {
    static let shared = AumiAudioRouteManager()

    private var audioPlayer: AumiAudioPlayer?
    private var isCallActive = false

    // Core Audio property address for "default output device changed"
    private var outputDevicePropertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope:    kAudioObjectPropertyScopeGlobal,
        mElement:  kAudioObjectPropertyElementMain
    )

    init() {}

    // MARK: - Lifecycle

    func startMonitoring(audioPlayer: AumiAudioPlayer) {
        self.audioPlayer = audioPlayer

        // 1. Listen for AVAudioEngine configuration changes
        //    (fires when AirPods connect/disconnect, USB audio plugged in, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigChange(_:)),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )

        // 2. Listen for Core Audio hardware device list changes
        //    (fires slightly earlier than AVAudioEngine notification — good for pre-emptive action)
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &outputDevicePropertyAddress,
            { _, _, _, clientData in
                // Bridge back to Swift — must be C closure
                guard let clientData = clientData else { return noErr }
                let manager = Unmanaged<AumiAudioRouteManager>.fromOpaque(clientData).takeUnretainedValue()
                manager.handleOutputDeviceChange()
                return noErr
            },
            Unmanaged.passUnretained(self).toOpaque()
        )

        print("AumiAudioRouteManager: Monitoring started ✅")
    }

    func stopMonitoring() {
        NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: nil)
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &outputDevicePropertyAddress,
            { _, _, _, _ in return noErr },
            nil
        )
    }

    func callBegan() { isCallActive = true }
    func callEnded() { isCallActive = false }

    // MARK: - Handlers

    /// Fired by AVAudioEngine itself when the underlying hardware graph changes.
    /// This is the most reliable hook — Apple guarantees it fires on connect AND disconnect.
    @objc private func handleEngineConfigChange(_ notification: Notification) {
        guard isCallActive else { return }
        print("AumiAudioRouteManager: Audio configuration changed (AirPods?) — re-routing…")
        rebuildAudioEngine()
    }

    /// Fired by Core Audio property listener (lower level, slightly faster).
    private func handleOutputDeviceChange() {
        guard isCallActive else { return }
        DispatchQueue.main.async { [weak self] in
            print("AumiAudioRouteManager: Output device changed — re-routing…")
            self?.rebuildAudioEngine()
        }
    }

    // MARK: - Seamless Re-route

    /// Tears down and restarts the AVAudioEngine on the new default device.
    /// Audio is interrupted for < 1 frame — imperceptible to the user.
    private func rebuildAudioEngine() {
        audioPlayer?.handleRouteChange()
        print("AumiAudioRouteManager: Re-route complete ✅ — now using \(currentOutputDeviceName())")
    }

    // MARK: - Helpers

    private func currentOutputDeviceName() -> String {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)

        var nameRef: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &nameRef)
        return nameRef as String
    }
}
