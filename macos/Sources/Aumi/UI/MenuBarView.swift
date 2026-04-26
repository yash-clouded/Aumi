import AppKit
import SwiftUI

class MenuBarController {
    private weak var statusItem: NSStatusItem?
    private var menu: NSMenu!
    private let callManager: CallManager
    private var statusMenuItem: NSMenuItem!
    private var latencyMenuItem: NSMenuItem!

    init(callManager: CallManager) {
        self.callManager = callManager
    }

    func configure(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        statusItem.button?.image = NSImage(systemSymbolName: "iphone.circle.fill",
                                           accessibilityDescription: "Aumi")
        statusItem.button?.image?.isTemplate = true
        buildMenu()
        statusItem.menu = menu
    }

    private func buildMenu() {
        menu = NSMenu()

        // Status row
        statusMenuItem = NSMenuItem(title: "Not Connected", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        latencyMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        latencyMenuItem.isEnabled = false
        menu.addItem(latencyMenuItem)

        menu.addItem(.separator())

        // Feature toggles
        addToggle(title: "Calls",           tag: 1)
        addToggle(title: "SMS",             tag: 2)
        addToggle(title: "Gmail",           tag: 3)
        addToggle(title: "Clipboard Sync",  tag: 4)

        menu.addItem(.separator())

        // Actions
        let mirror = NSMenuItem(title: "Mirror Screen",  action: #selector(mirrorScreen),  keyEquivalent: "")
        mirror.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: nil)
        mirror.target = self
        menu.addItem(mirror)

        let sms = NSMenuItem(title: "New Message", action: #selector(newMessage), keyEquivalent: "n")
        sms.image = NSImage(systemSymbolName: "bubble.left.fill", accessibilityDescription: nil)
        sms.target = self
        menu.addItem(sms)

        let file = NSMenuItem(title: "Send File", action: #selector(sendFile), keyEquivalent: "")
        file.image = NSImage(systemSymbolName: "arrow.up.doc.fill", accessibilityDescription: nil)
        file.target = self
        menu.addItem(file)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(NSMenuItem(title: "Quit Aumi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func addToggle(title: String, tag: Int) {
        let item = NSMenuItem(title: title, action: #selector(toggleFeature(_:)), keyEquivalent: "")
        item.state = .on
        item.tag = tag
        item.target = self
        menu.addItem(item)
    }

    // MARK: - Status Updates

    func setConnected(deviceName: String, latencyMs: Int) {
        DispatchQueue.main.async {
            self.statusMenuItem.title = "✅  \(deviceName)"
            self.latencyMenuItem.title = "Connected via LAN  •  \(latencyMs)ms"
            self.statusItem?.button?.image = NSImage(systemSymbolName: "iphone.circle.fill",
                                                    accessibilityDescription: "Aumi")
        }
    }

    func setDisconnected() {
        DispatchQueue.main.async {
            self.statusMenuItem.title = "Not Connected"
            self.latencyMenuItem.title = ""
        }
    }

    // MARK: - Actions

    @objc private func toggleFeature(_ sender: NSMenuItem) {
        sender.state = sender.state == .on ? .off : .on
    }

    @objc private func mirrorScreen() {
        ConnectionManager.shared.sendControl(["type": "SCREEN_STREAM_START"])
        ScreenMirrorWindow.show()
    }

    @objc private func newMessage() {
        let controller = NSHostingController(rootView: SMSComposeView())
        let window = NSWindow(contentViewController: controller)
        window.title = "New Message"
        window.setContentSize(NSSize(width: 420, height: 280))
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func sendFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                AumiFileTransferManager.shared.sendFile(url: url)
            }
        }
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
