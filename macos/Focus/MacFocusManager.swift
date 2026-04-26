import AppKit
import Foundation

/**
 * Tracks macOS user activity (keyboard, mouse, audio) to determine local focus.
 * Works with AumiFocusManager on Android to enable smart auto-switching.
 */
class MacFocusManager {
    static let shared = MacFocusManager()
    
    private var lastActivityTime = Date()
    private var activityTimer: Timer? = nil
    
    var isUserActive: Bool {
        return Date().timeIntervalSince(lastActivityTime) < 30 // Active if used in last 30s
    }

    func start() {
        // Monitor local keyboard and mouse events
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .mouseMoved, .scrollWheel]) { [weak self] event in
            self?.lastActivityTime = Date()
            return event
        }
        
        // Monitor global activity (even if Aumi isn't the active app)
        // Note: Requires Accessibility permissions in a real app
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] _ in
            self?.lastActivityTime = Date()
        }
        
        activityTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkAndReport()
        }
    }
    
    private func checkAndReport() {
        // Compare Mac score vs latest Android score received in ConnectionManager
        let macScore = calculateScore()
        
        // Notify ConnectionManager to potentially take/yield focus
        NotificationCenter.default.post(name: .aumiMacFocusChanged, object: nil, userInfo: ["score": macScore])
    }
    
    func calculateScore() -> Int {
        var score = 0
        if isUserActive { score += 60 }
        
        // Check if any audio is playing on Mac
        if isAudioPlaying() { score += 40 }
        
        return score
    }
    
    private func isAudioPlaying() -> Bool {
        // Simple heuristic: is any output audio session active
        // A deeper implementation would use CoreAudio property listeners
        return false // Placeholder
    }
}

extension Notification.Name {
    static let aumiMacFocusChanged = Notification.Name("aumiMacFocusChanged")
}
