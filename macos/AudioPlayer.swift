import AVFoundation
import CoreAudio

class AumiAudioPlayer {
    // Engine and nodes are vars so we can fully rebuild after a route change
    private var audioEngine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!

    // Queue to serialize all engine operations — prevents races during hot-swap
    private let engineQueue = DispatchQueue(label: "com.aumi.audioengine", qos: .userInteractive)

    // Pending audio buffers received during a route change are held here
    // and replayed once the new engine is ready
    private var pendingBuffers: [AVAudioPCMBuffer] = []
    private var isRebuilding = false

    init() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        buildGraph()
    }

    // MARK: - Graph Construction

    private func buildGraph() {
        audioEngine.attach(playerNode)
        // Always connect to mainMixerNode — AVAudioEngine will route to whatever
        // the current default output device is (built-in speakers, AirPods, USB DAC, etc.)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)

        do {
            try audioEngine.start()
            playerNode.play()
            print("AumiAudioPlayer: Engine started ✅ → \(currentOutputDeviceName())")
        } catch {
            print("AumiAudioPlayer: Failed to start engine: \(error)")
        }
    }

    // MARK: - Audio Scheduling (called from network receive loop)

    func scheduleAudio(pcmData: Data) {
        engineQueue.async { [weak self] in
            guard let self = self else { return }

            // Convert raw PCM Int16 → Float32 (AVAudioEngine native format)
            let frameCount = pcmData.count / 2  // 2 bytes per Int16 sample
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: self.format, frameCapacity: AVAudioFrameCount(frameCount))
            else { return }
            buffer.frameLength = AVAudioFrameCount(frameCount)

            pcmData.withUnsafeBytes { rawPointer in
                let int16Samples = rawPointer.bindMemory(to: Int16.self)
                if let floatChannelData = buffer.floatChannelData {
                    for i in 0..<frameCount {
                        // Normalise Int16 → Float32 in [-1.0, 1.0]
                        floatChannelData[0][i] = Float(int16Samples[i]) / 32768.0
                    }
                }
            }

            if self.isRebuilding {
                // Engine is hot-swapping — queue for replay
                self.pendingBuffers.append(buffer)
            } else {
                self.schedule(buffer: buffer)
            }
        }
    }

    private func schedule(buffer: AVAudioPCMBuffer) {
        guard audioEngine.isRunning else { return }
        playerNode.scheduleBuffer(buffer, at: nil, options: []) {
            // Buffer consumed
        }
    }

    // MARK: - Hot-Swap Handler (called by AumiAudioRouteManager)

    /// Called when AirPods connect OR disconnect mid-call.
    /// Tears down the old engine and rebuilds on the new default device in < 50ms.
    func handleRouteChange() {
        engineQueue.async { [weak self] in
            guard let self = self else { return }
            self.isRebuilding = true

            print("AumiAudioPlayer: Route change — stopping engine…")

            // 1. Gracefully stop the player node first to avoid click/pop
            self.playerNode.stop()
            self.audioEngine.stop()

            // 2. Detach old nodes cleanly
            self.audioEngine.detach(self.playerNode)

            // 3. Rebuild with fresh engine — AVAudioEngine will auto-detect
            //    the new default output device (AirPods / speakers / etc.)
            self.audioEngine = AVAudioEngine()
            self.playerNode = AVAudioPlayerNode()
            self.buildGraph()

            // 4. Drain pending buffers that arrived during the transition
            let drainBuffers = self.pendingBuffers
            self.pendingBuffers = []
            self.isRebuilding = false

            for buf in drainBuffers {
                self.schedule(buffer: buf)
            }

            print("AumiAudioPlayer: Route change complete ✅ — resumed on \(self.currentOutputDeviceName())")
        }
    }

    // MARK: - Helpers

    private func currentOutputDeviceName() -> String {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
        var nameRef: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &nameAddr, 0, nil, &nameSize, &nameRef)
        return nameRef as String
    }
}
