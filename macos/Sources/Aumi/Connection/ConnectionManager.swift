import Foundation
import Network
import CryptoKit

/**
 * The macOS connection manager. Implements:
 *  - TCP listener on port 8765: accepts Android connection, handles binary framing
 *  - UDP listener on port 8766: receives Opus audio packets
 *  - Encrypted send for all outbound messages
 *  - Routes incoming frames to subsystems (Call, SMS, Clipboard, Video, Audio)
 */
class ConnectionManager {
    static let shared = ConnectionManager()

    // MARK: - State
    private var tcpListener: NWListener?
    private var tcpConnection: NWConnection?
    private var udpListener: NWListener?
    internal var sessionKey: SymmetricKey?
    private var isRunning = false
    private var androidFocusScore: Int = 0

    private let tcpPort: NWEndpoint.Port = 8765
    private let udpPort: NWEndpoint.Port = 8766
    private let queue = DispatchQueue(label: "com.aumi.connection", qos: .userInteractive)

    // Subsystem wiring (set at app start)
    var callManager: CallManager?
    var videoDecoder: AumiVideoDecoder?
    var audioPlayer: AumiAudioPlayer?
    var clipboardManager: AumiClipboardManager?
    var fileTransferManager: AumiFileTransferManager?

    private init() {}

    // MARK: - Start / Stop

    func start() {
        refreshSessionKey()
        startTCPListener()
        startUDPListener()
        isRunning = true
    }

    func refreshSessionKey() {
        sessionKey = PairingManager.shared.loadSessionKey()
    }

    func stop() {
        tcpListener?.cancel()
        udpListener?.cancel()
        tcpConnection?.cancel()
        isRunning = false
    }

    // MARK: - TCP Listener (Control + Video)

    private func startTCPListener() {
        let params = NWParameters.tcp
        
        // Android 16 USB Tunnel Optimization: Force Dual Stack (IPv4 + IPv6)
        params.requiredLocalEndpoint = nil 
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = true
        
        if let ipOptions = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ipOptions.version = .any // Listen on both IPv4 and IPv6
        }

        guard let listener = try? NWListener(using: params, on: tcpPort) else { return }
        self.tcpListener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.tcpConnection?.cancel()  
            self?.tcpConnection = connection
            connection.start(queue: self?.queue ?? .main)
            self?.receiveNextFrame(connection: connection)
            
            // Visual feedback on Mac
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name("AumiConnected"), object: nil)
            }
            print("ConnectionManager: Android connected via TCP ✅")
        }
        listener.start(queue: queue)
    }

    // MARK: - Binary Frame Reader

    /// Reads frames in the format: [type(1)][len(4)][iv(12)][encrypted body]
    private func receiveNextFrame(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 5, maximumLength: 5) { [weak self] data, _, isComplete, error in
            guard let data = data, data.count == 5, error == nil else { 
                print("ConnectionManager: Failed to read frame header ❌ error: \(String(describing: error))")
                return 
            }
            
            let frameType = data[0]
            let bodyLen   = Int(data[1]) << 24 | Int(data[2]) << 16 | Int(data[3]) << 8 | Int(data[4])
            print("ConnectionManager: Incoming frame type: \(String(format: "0x%02X", frameType)), bodyLen: \(bodyLen) bytes")
            
            connection.receive(minimumIncompleteLength: 12 + bodyLen, maximumLength: 12 + bodyLen) { [weak self] frame, _, _, error in
                guard let frame = frame, error == nil else { 
                    print("ConnectionManager: Failed to read frame body ❌")
                    return 
                }
                self?.processFrame(type: frameType, frame: frame, bodyLen: bodyLen)
                self?.receiveNextFrame(connection: connection)
            }
        }
    }

    private func processFrame(type: UInt8, frame: Data, bodyLen: Int) {
        guard let key = sessionKey else { 
            print("ConnectionManager: Received frame but sessionKey is NIL! ❌")
            return 
        }
        let iv         = frame.prefix(12)
        let ciphertext = frame.suffix(from: 12)
        
        do {
            let plaintext = try AESCipher.decrypt(key: key, payload: iv + ciphertext)
            
            switch type {
            case 0x01:  // Control message
                if let json = try? JSONSerialization.jsonObject(with: plaintext) as? [String: Any] {
                    DispatchQueue.main.async { self.dispatchControl(json) }
                }
            case 0xF0:  // H.264 video
                if plaintext.count > 9 {
                    var pts: Int64 = 0
                    _ = withUnsafeMutableBytes(of: &pts) { plaintext.copyBytes(to: $0, from: 0..<8) }
                    let nalData = plaintext.suffix(from: 9)
                    DispatchQueue.global(qos: .userInteractive).async {
                        self.videoDecoder?.decode(data: nalData, pts: pts.bigEndian)
                    }
                }
            default:
                break
            }
        } catch {
            print("ConnectionManager: Decryption failed! Check session keys. ❌ error: \(error)")
        }
    }

    // MARK: - Control Dispatch

    private func dispatchControl(_ json: [String: Any]) {
        guard let type = json["type"] as? String else { return }
        switch type {
        case "CALL_EVENT":
            callManager?.handleCallEvent(json)
        case "CALL_INCOMING":
            // Android sends type=CALL_INCOMING directly — forward to CallManager
            var enriched = json
            enriched["event"] = "INCOMING"
            callManager?.handleCallEvent(enriched)
        case "CALL_DISCONNECTED":
            var enriched = json
            enriched["event"] = "CALL_DISCONNECTED"
            callManager?.handleCallEvent(enriched)
        case "SMS":
            NotificationBridge.shared.handleIncomingSMS(json)
        case "NOTIFICATION":
            NotificationBridge.shared.handleGmailNotification(json)
        case "CLIPBOARD":
            if let content = json["content"] as? String {
                clipboardManager?.receiveFromAndroid(content)
            }
        case "FOCUS_UPDATE":
            if let score = json["score"] as? Int {
                self.androidFocusScore = score
                arbitrateFocus()
            }
        case "FILE_TRANSFER_INIT":
            if let id = json["fileId"] as? String, let name = json["fileName"] as? String,
               let size = json["fileSize"] as? Int64 {
                fileTransferManager?.handleInit(fileId: id, name: name, size: size)
            }
        case "FILE_TRANSFER_CHUNK":
            if let id = json["fileId"] as? String, let data = json["data"] as? String {
                fileTransferManager?.handleChunk(fileId: id, dataBase64: data)
            }
        case "FILE_TRANSFER_COMPLETE":
            if let id = json["fileId"] as? String { fileTransferManager?.handleComplete(fileId: id) }
        case "HEARTBEAT":
            sendControl(["type": "HEARTBEAT_ACK"])
        default:
            break
        }
    }

    // MARK: - UDP Listener (Opus Audio)

    private func startUDPListener() {
        let params = NWParameters.udp
        guard let listener = try? NWListener(using: params, on: udpPort) else { return }
        self.udpListener = listener

        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .main)
            self?.receiveUDPPacket(connection: connection)
        }
        listener.start(queue: queue)
    }

    private func receiveUDPPacket(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] data, _, _, _ in
            guard let self = self, let data = data, data.count > 16 else {
                self?.receiveUDPPacket(connection: connection)
                return
            }
            // Format: seq(2) + iv(12) + len(2) + ciphertext
            let iv = data.subdata(in: 2..<14)
            let ctLen = Int(data[14]) << 8 | Int(data[15])
            if data.count >= 16 + ctLen, let key = self.sessionKey {
                let ct = data.subdata(in: 16..<(16 + ctLen))
                if let opus = try? AESCipher.decrypt(key: key, payload: iv + ct) {
                    DispatchQueue.global(qos: .userInteractive).async {
                        self.audioPlayer?.scheduleAudio(pcmData: opus)
                    }
                }
            }
            self.receiveUDPPacket(connection: connection)
        }
    }

    // MARK: - Outbound Sending

    /// Sends an encrypted control message over TCP.
    func sendControl(_ dict: [String: Any]) {
        guard let key = sessionKey,
              let connection = tcpConnection,
              let body = try? JSONSerialization.data(withJSONObject: dict),
              let encrypted = try? AESCipher.encrypt(key: key, plaintext: body) else { return }

        var frame = Data()
        frame.append(0x01)  // type
        let len = encrypted.count - 12  // exclude IV from body length
        frame.append(contentsOf: [UInt8((len >> 24) & 0xFF), UInt8((len >> 16) & 0xFF),
                                   UInt8((len >> 8) & 0xFF), UInt8(len & 0xFF)])
        frame.append(encrypted)  // IV(12) + ciphertext
        connection.send(content: frame, completion: .idempotent)
    }

    private func handleTCPError() {
        print("ConnectionManager: TCP connection lost — waiting for Android to reconnect")
        tcpConnection = nil
    }

    // MARK: - Smart Auto-Switching Arbitration

    private func arbitrateFocus() {
        let macScore = MacFocusManager.shared.calculateScore()
        
        // If Android has extremely high focus (Picked up + Screen On) and Mac is idle, 
        // we might want to "Yield" focus back to the phone.
        if androidFocusScore > 75 && macScore < 20 {
            print("ConnectionManager: Yielding focus to Android Phone (User picked up phone)")
            // TODO: Minimize mirroring window or suggest "Continue on Phone"
        }
    }
}
