import Foundation
import Network
import Starscream

class AumiNetworkManager: NSObject {
    static let shared = AumiNetworkManager()
    
    private var socket: WebSocket?
    private var browser: NWBrowser?
    private var lanConnection: NWConnection?
    
    // Set these after QR pairing
    var relayURL: URL = URL(string: "ws://your-relay-server:8080")!
    var targetDeviceId: String = "android_phone"
    
    private let deviceID: String = {
        Host.current().localizedName ?? "macbook_pro"
    }()
    
    // Subsystem managers – wired up at app startup
    var callWindowManager: CallWindowManager?
    var clipboardManager: AumiClipboardManager?
    var fileTransferManager: AumiFileTransferManager?
    var videoDecoder: AumiVideoDecoder?
    
    func start() {
        startLocalDiscovery()
        connectToRelay()
    }
    
    // MARK: - Outgoing
    func sendMessage(_ payload: [String: Any]) {
        var full = payload
        full["targetId"] = targetDeviceId
        guard let data = try? JSONSerialization.data(withJSONObject: full),
              let string = String(data: data, encoding: .utf8) else { return }
        
        // Prefer LAN if ready
        if let conn = lanConnection, conn.state == .ready {
            let msg = string + "\n"
            conn.send(content: msg.data(using: .utf8), completion: .idempotent)
        } else {
            socket?.write(string: string)
        }
    }
    
    // MARK: - Local Discovery (mDNS)
    private func startLocalDiscovery() {
        let parameters = NWParameters.tcp
        browser = NWBrowser(for: .bonjour(type: "_aumi._tcp", domain: nil), using: parameters)
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            // Connect to the first found Android device; avoid re-connecting if already ready
            if self.lanConnection?.state != .ready, let result = results.first {
                self.connectToLocalDevice(endpoint: result.endpoint)
            }
        }
        browser?.start(queue: .global(qos: .utility))
    }
    
    private func connectToLocalDevice(endpoint: NWEndpoint) {
        lanConnection = NWConnection(to: endpoint, using: .tcp)
        lanConnection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Aumi: Connected to Android via LAN ✅")
                self?.setupLANReceive()
            case .failed(let error):
                print("Aumi: LAN connection failed: \(error). Will retry via relay.")
                self?.lanConnection = nil
            default: break
            }
        }
        lanConnection?.start(queue: .global(qos: .userInitiated))
    }
    
    // MARK: - Relay Connection (WebSocket fallback)
    private func connectToRelay() {
        var request = URLRequest(url: relayURL)
        request.timeoutInterval = 10
        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()
    }
    
    // MARK: - Receive Loop (LAN)
    private func setupLANReceive() {
        lanConnection?.receive(minimumIncompleteLength: 1, maximumLength: 131_072) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self?.dispatch(data: data)
            }
            if error == nil && !isComplete {
                self?.setupLANReceive() // Re-arm receive
            } else {
                self?.lanConnection = nil // Trigger relay fallback
            }
        }
    }
    
    // MARK: - Message Dispatch
    func dispatch(data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch type {
            case "CALL_INCOMING":
                let name   = json["name"]   as? String ?? "Unknown"
                let number = json["number"] as? String ?? ""
                let callId = json["id"]     as? String ?? ""
                self.callWindowManager?.showCall(name: name, number: number, callId: callId)

            case "CALL_DISCONNECTED":
                // Call ended (remote hang-up or missed) — stop AirPods monitoring
                sharedRouteManager.callEnded()
                sharedRouteManager.stopMonitoring()
                
            case "CLIPBOARD_SYNC":
                if let content = json["content"] as? String {
                    self.clipboardManager?.receiveFromAndroid(content)
                }
                
            case "FILE_TRANSFER_INIT":
                if let fileId = json["fileId"] as? String,
                   let name = json["fileName"] as? String,
                   let size = json["fileSize"] as? Int64 {
                    self.fileTransferManager?.handleInit(fileId: fileId, name: name, size: size)
                }
                
            case "FILE_TRANSFER_CHUNK":
                if let fileId = json["fileId"] as? String,
                   let dataStr = json["data"] as? String {
                    self.fileTransferManager?.handleChunk(fileId: fileId, dataBase64: dataStr)
                }
                
            case "FILE_TRANSFER_COMPLETE":
                if let fileId = json["fileId"] as? String {
                    self.fileTransferManager?.handleComplete(fileId: fileId)
                }
                
            case "SCREEN_STREAM_DATA":
                if let dataStr = json["data"] as? String,
                   let rawData = Data(base64Encoded: dataStr),
                   let pts = json["pts"] as? Int64 {
                    // Off main thread for decode
                    DispatchQueue.global(qos: .userInteractive).async {
                        self.videoDecoder?.decode(data: rawData, pts: pts)
                    }
                }
                
            default:
                print("Aumi: Unhandled message type: \(type)")
            }
        }
    }
}

// MARK: - WebSocket Delegate (Relay)
extension AumiNetworkManager: WebSocketDelegate {
    func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected:
            print("Aumi: Relay connected ✅")
            let registerMsg: [String: Any] = ["type": "REGISTER", "deviceId": deviceID]
            sendMessage(registerMsg)
            
        case .text(let string):
            if let data = string.data(using: .utf8) {
                dispatch(data: data)
            }
            
        case .disconnected(let reason, _):
            print("Aumi: Relay disconnected (\(reason)). Reconnecting in 3s...")
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.connectToRelay()
            }
            
        case .error(let error):
            print("Aumi: Relay error: \(String(describing: error))")
            
        default: break
        }
    }
}
