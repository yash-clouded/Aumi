import AppKit
import SwiftUI

@main
struct AumiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate!
    
    var statusItem: NSStatusItem!
    var menuBarController: MenuBarController!
    var callManager = CallManager()
    private var pairingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        // 1. Wire all subsystems into ConnectionManager
        let conn = ConnectionManager.shared
        conn.callManager        = callManager
        conn.videoDecoder       = AumiVideoDecoder()
        conn.audioPlayer        = sharedAudioPlayer
        conn.clipboardManager   = AumiClipboardManager.shared
        conn.fileTransferManager = AumiFileTransferManager.shared

        // Wire call manager → audio route manager
        callManager.audioPlayer  = sharedAudioPlayer
        callManager.routeManager = sharedRouteManager

        // Pairing UI Listeners
        NotificationCenter.default.addObserver(forName: NSNotification.Name("AumiConnected"), object: nil, queue: .main) { [weak self] _ in
            self?.pairingWindow?.close()
            self?.menuBarController.setConnected(deviceName: "Samsung S24 (Android 16)", latencyMs: 5)
        }

        // 2. Start subsystems
        AumiClipboardManager.shared.start()

        // 3. Start network listener
        ConnectionManager.shared.start()

        // 4. Register for system sleep/wake
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )

        // 5. Build menu bar icon
        menuBarController = MenuBarController(callManager: callManager)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menuBarController.configure(statusItem: statusItem)

        // 6. Always show pairing window — it will auto-dismiss once connected
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.showPairingWindow()
        }
    }

    // MARK: - Sleep / Wake

    @objc private func systemWillSleep() {
        ConnectionManager.shared.stop()
    }

    @objc private func systemDidWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            ConnectionManager.shared.start()
        }
    }

    // MARK: - Pairing Window

    func showPairingWindow() {
        if let existing = pairingWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let controller = NSHostingController(rootView: PairingView())
        let window = NSWindow(contentViewController: controller)
        window.title = "Aumi — Pair your Android"
        window.setContentSize(NSSize(width: 480, height: 560))
        window.styleMask = [.titled, .closable]
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.pairingWindow = window
    }
}
