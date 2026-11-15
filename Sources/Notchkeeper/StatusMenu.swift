import AppKit
import ServiceManagement

// Menu bar icon: the one place to connect, launch at login and quit, even with no sessions to hover.
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store: SessionStore
    // Re-places the notch when the display setting changes.
    var onPlacementChange: (() -> Void)?
    var onSettings: (() -> Void)?

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
        menu.addItem(NSMenuItem(title: "Agents", action: nil, keyEquivalent: ""))
        // A check means Notchkeeper's hooks are in that agent's settings; click to connect or disconnect.
        for agent in Agent.allCases where agent == .claude || agent.isInstalled {
            let item = add(menu, agent.title, #selector(toggleConnect(_:)))
            item.representedObject = agent.rawValue
            item.state = HookInstaller.isConnected(agent) ? .on : .off
            item.indentationLevel = 1
        }
        menu.addItem(.separator())
        add(menu, "New Background Agent…", #selector(newAgent))
        menu.addItem(.separator())
        add(menu, "Sounds", #selector(toggleSounds)).state = store.sounds ? .on : .off
        add(menu, "Quiet Mode", #selector(toggleQuiet)).state = store.quiet ? .on : .off
        menu.addItem(pluginsItem())
        add(menu, "Show on Active Display", #selector(toggleFollow)).state = NotchPanel.followsActiveDisplay ? .on : .off
        add(menu, "Approval Log…", #selector(openLog))
        add(menu, "Launch at Login", #selector(toggleLogin)).state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        add(menu, "Open Notchkeeper…", #selector(openSettings), key: ",")
        add(menu, "Quit Notchkeeper", #selector(quit), key: "q")
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleConnect(_ sender: NSMenuItem) {
        guard let agent = (sender.representedObject as? String).flatMap(Agent.init) else { return }
        do {
            if HookInstaller.isConnected(agent) {
                try HookInstaller.disconnect(agent)
            } else if agent == .claude {
                // Claude's settings are asked about in the notch, with the details.
                store.connectError = nil
                store.offerConnect = true
            } else {
                try HookInstaller.connect(agent)
                // Codex runs new hooks only after you approve them.
                if agent == .codex { tell("Codex connected", "Open Codex and approve Notchkeeper's hooks with /hooks. Until then Codex won't run them.") }
            }
        } catch {
            tell("Couldn't change \(agent.title)'s hooks", error.localizedDescription)
        }
    }

    private func tell(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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
    // Plugins submenu: one checkable row per plugin found, plus the folder and the bundled examples.
    private func pluginsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Plugins", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let plugins = Plugins.all
        if plugins.isEmpty { sub.addItem(NSMenuItem(title: "No plugins yet", action: nil, keyEquivalent: "")) }
        for plugin in plugins {
            let row = add(sub, plugin.name, #selector(togglePlugin(_:)))
            row.representedObject = plugin.id
            row.state = Plugins.enabled.contains(plugin.id) ? .on : .off
            row.toolTip = plugin.description
        }
        sub.addItem(.separator())
        add(sub, "Add Example Plugins", #selector(addExamples))
        add(sub, "Open Plugins Folder", #selector(openPlugins))
        item.submenu = sub
        return item
    }

    @objc private func togglePlugin(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if Plugins.enabled.contains(id) { Plugins.enabled.remove(id) } else { Plugins.enabled.insert(id) }
    }

    @objc private func addExamples() { Plugins.installExamples(); openPlugins() }
    @objc private func openPlugins() { Plugins.openFolder() }
    @objc private func openSettings() { onSettings?() }

    @objc private func toggleFollow() {
        NotchPanel.followsActiveDisplay.toggle()
        onPlacementChange?()
    }
    @objc private func toggleSounds() { store.sounds.toggle() }
    @objc private func toggleQuiet() { store.quiet.toggle() }

    @objc private func openLog() { AuditLog.open() }

    @objc private func quit() { NSApp.terminate(nil) }
}
