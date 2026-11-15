import AppKit
import ServiceManagement

// Menu bar icon: the one place to connect, launch at login and quit, even with no sessions to hover.
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store: SessionStore

    init(store: SessionStore) {
        self.store = store
        super.init()
        item.button?.image = NSImage(systemSymbolName: "wave.3.right", accessibilityDescription: "Ping")
        item.menu = NSMenu()
        item.menu?.delegate = self
    }

    // Rebuilt on every open, so it always reflects the current settings file.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let connected = HookInstaller.isConnected
        menu.addItem(NSMenuItem(title: connected ? "Connected to Claude Code" : "Not connected to Claude Code", action: nil, keyEquivalent: ""))
        add(menu, connected ? "Disconnect" : "Connect…", #selector(toggleConnect))
        menu.addItem(.separator())
        add(menu, "Launch at Login", #selector(toggleLogin)).state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        add(menu, "Quit Ping", #selector(quit), key: "q")
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleConnect() {
        if HookInstaller.isConnected {
            do { try HookInstaller.disconnect() } catch { NSLog("Ping: \(error.localizedDescription)") }
        } else {
            store.connectError = nil
            store.offerConnect = true
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Ping: launch at login failed: \(error)")
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
