import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SessionStore()
    var panel: NotchPanel?
    var server: EventServer?
    var menu: StatusMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = NotchPanel(store: store)
        panel?.orderFrontRegardless()
        menu = StatusMenu(store: store)

        HookInstaller.refreshScripts()
        store.renamedFromPing = HookInstaller.hasLegacyHooks
        store.offerConnect = !HookInstaller.isConnected && (store.renamedFromPing || !UserDefaults.standard.bool(forKey: "declinedConnect"))

        // Private to you: whoever can reach the socket can answer approvals.
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notchkeeper")
        let privateDir: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: privateDir)
        try? FileManager.default.setAttributes(privateDir, ofItemAtPath: dir.path)
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
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.panel?.place() }
    }
}
