import AppKit
import Foundation

class AumiClipboardManager {
    static let shared = AumiClipboardManager()
    
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var lastSyncedText: String = ""
    
    private var timer: Timer?
    
    func start() {
        // Poll for clipboard changes (macOS doesn't have a direct listener for all apps)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    private func checkClipboard() {
        if pasteboard.changeCount != lastChangeCount {
            lastChangeCount = pasteboard.changeCount
            if let text = pasteboard.string(forType: .string), text != lastSyncedText {
                lastSyncedText = text
                syncToAndroid(text)
            }
        }
    }
    
    private func syncToAndroid(_ text: String) {
        let payload: [String: Any] = [
            "type": "CLIPBOARD_SYNC",
            "content": text,
            "timestamp": Date().timeIntervalSince1970
        ]
        // AumiNetworkManager.shared.sendMessage(payload)
        print("Syncing clipboard to Android: \(text)")
    }
    
    func receiveFromAndroid(_ text: String) {
        if text != lastSyncedText {
            lastSyncedText = text
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            lastChangeCount = pasteboard.changeCount
            print("Received clipboard from Android: \(text)")
        }
    }
}
