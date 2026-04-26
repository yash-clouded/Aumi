import SwiftUI
import AVFoundation

/// In-call UI shown after the user answers a call from the Mac.
class CallManager {
    var audioPlayer: AumiAudioPlayer?
    var routeManager: AumiAudioRouteManager?
    private var callWindowManager = CallWindowManager()
    private var activeCallWindow: NSWindow?
    private var ringtonePlayer: AVAudioPlayer?
    private var callTimer: Timer?
    private var callDuration = 0

    func handleCallEvent(_ json: [String: Any]) {
        let event = json["event"] as? String ?? json["type"] as? String ?? ""
        switch event {
        case "INCOMING", "CALL_INCOMING":
            let name   = json["name"]   as? String ?? json["contactName"] as? String ?? "Unknown"
            let number = json["number"] as? String ?? ""
            let callId = json["id"]     as? String ?? ""
            startRingtone()
            callWindowManager.showCall(name: name, number: number, callId: callId)

        case "ANSWERED_ON_PHONE":
            stopRingtone()
            showActiveCallWindow(callerName: json["name"] as? String ?? "Call Active")

        case "CALL_ENDED", "DISCONNECTED", "CALL_DISCONNECTED":
            stopRingtone()
            callTimer?.invalidate()
            activeCallWindow?.close()
            routeManager?.callEnded()
            routeManager?.stopMonitoring()
            postMissedCallIfNeeded(json)

        case "MISSED":
            stopRingtone()
            postMissedCallNotification(name: json["name"] as? String ?? "Unknown",
                                       number: json["number"] as? String ?? "")
        default:
            break
        }
    }

    // MARK: - Ringtone
    private func startRingtone() {
        guard let url = Bundle.main.url(forResource: "ringtone", withExtension: "caf") ??
              Bundle.main.url(forResource: "ringtone", withExtension: "mp3") else { return }
        ringtonePlayer = try? AVAudioPlayer(contentsOf: url)
        ringtonePlayer?.numberOfLoops = -1  // Infinite loop
        ringtonePlayer?.play()
    }

    private func stopRingtone() {
        ringtonePlayer?.stop()
        ringtonePlayer = nil
    }

    // MARK: - Active Call Window
    private func showActiveCallWindow(callerName: String) {
        let view = ActiveCallView(callerName: callerName, onHangUp: { [weak self] in
            self?.hangUp()
        }, onMute: { muted in
            // TODO: mute Mac mic capture
        })
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        window.isOpaque      = false
        window.backgroundColor = .clear
        window.contentViewController = controller
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.activeCallWindow = window

        callDuration = 0
        callTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.callDuration += 1
        }
    }

    private func hangUp() {
        ConnectionManager.shared.sendControl(["type": "CALL_DECLINE", "id": ""])
        callTimer?.invalidate()
        activeCallWindow?.close()
        routeManager?.callEnded()
        routeManager?.stopMonitoring()
    }

    // MARK: - Missed Call Notification
    private func postMissedCallIfNeeded(_ json: [String: Any]) {
        // Only post if call was never answered
    }

    private func postMissedCallNotification(name: String, number: String) {
        let content = UNMutableNotificationContent()
        content.title = "Missed Call"
        content.body  = "\(name) (\(number))"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

// MARK: - Active Call SwiftUI View
private struct ActiveCallView: View {
    let callerName: String
    let onHangUp: () -> Void
    let onMute: (Bool) -> Void
    @State private var isMuted = false
    @State private var seconds = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            Text(callerName).font(.headline)
            Text(formatDuration(seconds))
                .font(.subheadline).foregroundStyle(.secondary)
                .onReceive(timer) { _ in seconds += 1 }

            HStack(spacing: 20) {
                Button {
                    isMuted.toggle()
                    onMute(isMuted)
                } label: {
                    Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                        .foregroundStyle(isMuted ? .red : .primary)
                        .padding(12)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button(action: onHangUp) {
                    Image(systemName: "phone.down.fill")
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
        .cornerRadius(16)
    }

    private func formatDuration(_ s: Int) -> String {
        String(format: "%02d:%02d", s / 60, s % 60)
    }
}
