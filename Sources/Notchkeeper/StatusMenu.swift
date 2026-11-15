import AppKit
import ServiceManagement

// Menu bar icon: the one place to connect, launch at login and quit, even with no sessions to hover.
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store: SessionStore

    init(store: SessionStore) {
        self.store = store
        super.init()
        item.button?.image = NSImage(systemSymbolName: "wave.3.right", accessibilityDescription: "Notchkeeper")
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
        add(menu, "New Background Agent…", #selector(newAgent))
        menu.addItem(.separator())
        add(menu, "Sounds", #selector(toggleSounds)).state = store.sounds ? .on : .off
        add(menu, "Quiet Mode", #selector(toggleQuiet)).state = store.quiet ? .on : .off
        add(menu, "Approval Log…", #selector(openLog))
        add(menu, "Launch at Login", #selector(toggleLogin)).state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        add(menu, "Quit Notchkeeper", #selector(quit), key: "q")
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleConnect() {
        if HookInstaller.isConnected {
            do { try HookInstaller.disconnect() } catch { NSLog("Notchkeeper: \(error.localizedDescription)") }
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
            NSLog("Notchkeeper: launch at login failed: \(error)")
        }
    }

    @objc private func newAgent() { store.openNewAgent() }
    @objc private func toggleSounds() { store.sounds.toggle() }
    @objc private func toggleQuiet() { store.quiet.toggle() }

    // Opens as plain text; the file only exists after the first answer.
    @objc private func openLog() {
        if !FileManager.default.fileExists(atPath: AuditLog.path) {
            FileManager.default.createFile(atPath: AuditLog.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        NSWorkspace.shared.open([URL(fileURLWithPath: AuditLog.path)], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
