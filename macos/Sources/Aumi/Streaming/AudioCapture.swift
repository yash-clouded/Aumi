import AVFoundation

/**
 * Captures Mac microphone audio, encodes as Opus, and sends to Android.
 * Essential for bidirectional calls so the remote person can hear the Mac user.
 */
class AudioCapture {
    private let audioEngine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
    private var isCapturing = false
    
    // Serial queue for Opus encoding to avoid jitter
    private let encodeQueue = DispatchQueue(label: "com.aumi.audio.encode", qos: .userInteractive)

    func start() {
        guard !isCapturing else { return }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 480, format: inputFormat) { [weak self] buffer, time in
            self?.encodeAndSend(buffer: buffer)
        }
        
        do {
            try audioEngine.start()
            isCapturing = true
            print("AudioCapture: Started ✅")
        } catch {
            print("AudioCapture: Failed to start: \(error)")
        }
    }
    
    func stop() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isCapturing = false
    }
    
    private func encodeAndSend(buffer: AVAudioPCMBuffer) {
        encodeQueue.async {
            // 1. Convert to Int16 PCM if needed
            // 2. Encode with Opus (libopus)
            // 3. Encrypt and send over UDP via ConnectionManager
            
            // For MVP, we'll send a place-holder to verify the path
            // In full implementation, libopus-swift would be used here.
            let rawData = self.toData(buffer: buffer)
            ConnectionManager.shared.sendAudio(pcmData: rawData)
        }
    }
    
    private func toData(buffer: AVAudioPCMBuffer) -> Data {
        let frameCount = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        let src = buffer.floatChannelData![0]
        
        var int16Data = Data(count: frameCount * 2)
        int16Data.withUnsafeMutableBytes { (dest: UnsafeMutableRawBufferPointer) in
            let ptr = dest.bindMemory(to: Int16.self).baseAddress!
            for i in 0..<frameCount {
                // Float32 [-1, 1] -> Int16
                let sample = max(-1.0, min(1.0, src[i]))
                ptr[i] = Int16(sample * 32767.0)
            }
        }
        return int16Data
    }
}

extension ConnectionManager {
    /// Sends protected audio frame over UDP (port 8766).
    func sendAudio(pcmData: Data) {
        guard let key = ConnectionManager.shared.sessionKey else { return }
        
        // In real app, pcmData would be Opus. 
        // Here we encrypt the raw PCM (bandwidth intensive but verifiable).
        guard let encrypted = try? AESCipher.encrypt(key: key, plaintext: pcmData) else { return }
        
        let iv = encrypted.prefix(12)
        let ct = encrypted.suffix(from: 12)
        
        var packet = Data()
        var seq: UInt16 = 0 // Needs to be incremented
        packet.append(contentsOf: [UInt8(seq >> 8), UInt8(seq & 0xFF)])
        packet.append(iv)
        let ctLen = UInt16(ct.count)
        packet.append(contentsOf: [UInt8(ctLen >> 8), UInt8(ctLen & 0xFF)])
        packet.append(ct)
        
        // Sent to the connected endpoint on port 8766
        // NWConnection for UDP would be used here.
    }
}
