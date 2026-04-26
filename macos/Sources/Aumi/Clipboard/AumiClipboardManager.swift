import AppKit

class AumiClipboardManager {
    static let shared = AumiClipboardManager()
    
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount = NSPasteboard.general.changeCount
    
    func start() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    private func checkClipboard() {
        if pasteboard.changeCount != lastChangeCount {
            lastChangeCount = pasteboard.changeCount
            if let str = pasteboard.string(forType: .string) {
                syncToAndroid(str)
            }
        }
    }
    
    func receiveFromAndroid(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount // avoid loop
    }
    
    private func syncToAndroid(_ text: String) {
        ConnectionManager.shared.sendControl([
            "type": "CLIPBOARD",
            "content": text
        ])
    }
}
