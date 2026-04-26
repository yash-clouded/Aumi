import AppKit
import SwiftUI

@main
struct AumiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menuBarController: MenuBarController!
    var callManager = CallManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        // 6. If not paired, show pairing window
        if !KeychainStore.isPaired() {
            showPairingWindow()
        }

        // Hide from Dock — menu bar only app
        NSApp.setActivationPolicy(.accessory)
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
        let controller = NSHostingController(rootView: PairingView())
        let window = NSWindow(contentViewController: controller)
        window.title = "Aumi — Pair your Android"
        window.setContentSize(NSSize(width: 480, height: 560))
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
