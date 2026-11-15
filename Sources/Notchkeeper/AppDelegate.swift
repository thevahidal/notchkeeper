import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SessionStore()
    var panel: NotchPanel?
    var server: EventServer?
    var menu: StatusMenu?
    lazy var settings = SettingsModel(store: store)
    lazy var watches = Watches(store: store)
    private var saver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = NotchPanel(store: store)
        panel?.orderFrontRegardless()
        menu = StatusMenu(store: store)
        menu?.onPlacementChange = { [weak self] in self?.panel?.place() }
        menu?.onSettings = { [weak self] in self?.showSettings() }
        settings.onPlacementChange = { [weak self] in self?.panel?.place() }

        HookInstaller.refreshScripts()
        Plugins.retireOldExamples()
        store.restore()
        try? FileManager.default.removeItem(at: SessionStore.pasteDir)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let paste = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command && event.charactersIgnoringModifiers == "v"
            return paste && self?.store.pasteImage() == true ? nil : event
        }
        // Written a second after the last change, not on every event.
        saver = store.$sessions.debounce(for: .seconds(1), scheduler: RunLoop.main).sink { [weak self] _ in self?.store.save() }
        store.renamedFromPing = HookInstaller.hasLegacyHooks
        store.offerConnect = !HookInstaller.isConnected() && (store.renamedFromPing || !UserDefaults.standard.bool(forKey: "declinedConnect"))

        // Private to you: whoever can reach the socket can answer approvals.
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notchkeeper")
        let privateDir: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: privateDir)
        try? FileManager.default.setAttributes(privateDir, ofItemAtPath: dir.path)
        linkCommand(in: dir)
        do {
            server = try EventServer(path: dir.appendingPathComponent("notchkeeper.sock").path) { [weak self] event, reply in
                self?.store.apply(event, reply: reply)
            }
        } catch {
            NSLog("Notchkeeper: could not start event server: \(error)")
        }

        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.store.checkPresence() }
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.store.pruneStale()
            self?.store.remind()
            Plugins.emit("tick", nil)
        }

        // First launch: show what can be set up.
        if !UserDefaults.standard.bool(forKey: "launchedBefore") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            showSettings(.settings)
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.panel?.place() }
    }

    func showSettings(_ pane: SettingsModel.Pane? = nil) { SettingsWindow.show(settings, watches, pane: pane) }

    func applicationWillTerminate(_ notification: Notification) { watches.stopAll() }

    // Opening the app again (Finder, Spotlight, `open`) shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    // ~/.notchkeeper/bin/notchkeeper → this app, so `notchkeeper notify` / `run` work wherever the app lives.
    private func linkCommand(in dir: URL) {
        guard let executable = Bundle.main.executablePath else { return }
        let bin = dir.appendingPathComponent("bin")
        let link = bin.appendingPathComponent("notchkeeper").path
        let fm = FileManager.default
        try? fm.createDirectory(at: bin, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard (try? fm.destinationOfSymbolicLink(atPath: link)) != executable else { return }
        try? fm.removeItem(atPath: link)
        try? fm.createSymbolicLink(atPath: link, withDestinationPath: executable)
    }
}
