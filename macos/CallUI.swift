import SwiftUI
import AppKit

// Shared instances — created once at app start
let sharedAudioPlayer  = AumiAudioPlayer()
let sharedRouteManager = AumiAudioRouteManager.shared

struct IncomingCallView: View {
    let callerName: String
    let callerNumber: String
    var onAnswer: () -> Void
    var onDecline: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Caller Avatar
            Circle()
                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(String(callerName.first ?? "U"))
                        .font(.title)
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(callerName)
                    .font(.headline)
                Text(callerNumber)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: onDecline) {
                    Image(systemName: "phone.down.fill")
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                
                Button(action: onAnswer) {
                    Image(systemName: "phone.fill")
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.green)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 320, height: 80)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
        .cornerRadius(16)
        .shadow(radius: 10)
    }
}

// Helper for Background Blur
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

class CallWindowManager {
    private var window: NSWindow?
    
    private var currentCallId: String = ""

    func showCall(name: String, number: String, callId: String = "") {
        currentCallId = callId
        let view = IncomingCallView(callerName: name, callerNumber: number, onAnswer: {
            self.answer()
        }, onDecline: {
            self.decline()
        })
        
        let hostingController = NSHostingController(rootView: view)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.contentViewController = hostingController
        window?.level = .floating
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
    
    func answer() {
        // Tell route manager a call is now active — AirPods monitoring begins
        sharedRouteManager.startMonitoring(audioPlayer: sharedAudioPlayer)
        sharedRouteManager.callBegan()

        // Send CALL_ANSWER to Android so the phone actually picks up
        AumiNetworkManager.shared.sendMessage([
            "type": "CALL_ANSWER",
            "id": currentCallId
        ])
        dismiss()
    }
    
    func decline() {
        // Send CALL_DECLINE to Android so the phone rejects the call
        AumiNetworkManager.shared.sendMessage([
            "type": "CALL_DECLINE",
            "id": currentCallId
        ])
        dismiss()
    }
    
    private func dismiss() {
        window?.close()
        window = nil
    }
}
