import AppKit
import SwiftUI

class CallWindowManager {
    private var incomingCallWindow: NSWindow?

    func showCall(name: String, number: String, callId: String) {
        let view = IncomingCallView(name: name, number: number) { [weak self] accepted in
            if accepted {
                ConnectionManager.shared.sendControl(["type": "CALL_ANSWER", "id": callId])
            } else {
                ConnectionManager.shared.sendControl(["type": "CALL_DECLINE", "id": callId])
            }
            self?.incomingCallWindow?.close()
        }
        
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.borderless]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver  // Above everything including full-screen apps
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.incomingCallWindow = window
    }
}

struct IncomingCallView: View {
    let name: String
    let number: String
    let onResponse: (Bool) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(name).font(.title3).bold()
            Text(number).font(.subheadline).foregroundStyle(.secondary)
            
            HStack(spacing: 40) {
                Button { onResponse(false) } label: {
                    Image(systemName: "phone.down.fill")
                        .padding(16)
                        .background(Color.red)
                        .clipShape(Circle())
                }.buttonStyle(.plain)
                
                Button { onResponse(true) } label: {
                    Image(systemName: "phone.fill")
                        .padding(16)
                        .background(Color.green)
                        .clipShape(Circle())
                }.buttonStyle(.plain)
            }
        }
        .padding(30)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
        .cornerRadius(24)
    }
}
