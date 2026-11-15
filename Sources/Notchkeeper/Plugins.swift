import AppKit

// Plugins: folders in ~/.notchkeeper/plugins, each with a plugin.json and a script.
// Notchkeeper runs a plugin's script when one of its events happens, with the event as JSON on stdin.
// Off until you turn each one on; scripts run directly (no shell) and only from inside their own folder.
struct Plugin: Identifiable {
    let id: String
    let name: String
    let description: String
    let executable: String
    let events: Set<String>
}

enum Plugins {
    static let folder = HookInstaller.home + "/.notchkeeper/plugins"
    static let events = ["needs-you", "done", "approval"]

    static var all: [Plugin] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: folder)) ?? []
        return names.sorted().compactMap { name in
            let dir = (folder + "/" + name as NSString).standardizingPath
            guard let data = fm.contents(atPath: dir + "/plugin.json"),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let run = manifest["run"] as? String else { return nil }
            // The script must live inside the plugin's folder.
            let executable = (dir + "/" + run as NSString).standardizingPath
            guard executable.hasPrefix(dir + "/"), fm.isExecutableFile(atPath: executable) else { return nil }
            return Plugin(id: name, name: manifest["name"] as? String ?? name, description: manifest["description"] as? String ?? "",
                          executable: executable, events: Set(manifest["on"] as? [String] ?? []))
        }
    }

    static var enabled: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "enabledPlugins") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "enabledPlugins") }
    }

    static func emit(_ event: String, _ session: Session, extra: [String: Any] = [:]) {
        let targets = all.filter { enabled.contains($0.id) && $0.events.contains(event) }
        guard !targets.isEmpty else { return }
        var payload: [String: Any] = [
            "event": event,
            "session": [
                "id": session.id, "title": session.title.isEmpty ? session.repo : session.title, "repo": session.repo,
                "agent": session.agent ?? "claude", "detail": session.question ?? session.detail, "url": session.url ?? "",
            ],
        ]
        payload.merge(extra) { $1 }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        for plugin in targets { run(plugin, data) }
    }

    // Each run gets 10 seconds; a hung plugin can't pile up.
    private static func run(_ plugin: Plugin, _ input: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: plugin.executable)
        process.currentDirectoryURL = URL(fileURLWithPath: (plugin.executable as NSString).deletingLastPathComponent)
        process.environment = ["HOME": HookInstaller.home, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"]
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return NSLog("Notchkeeper: plugin \(plugin.id) didn't start") }
        stdin.fileHandleForWriting.write(input)
        try? stdin.fileHandleForWriting.close()
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { if process.isRunning { process.terminate() } }
    }

    // Copies the bundled example plugins into the plugins folder, leaving any you already have alone.
    static func installExamples() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let examples = Bundle.main.resourcePath.map({ $0 + "/plugins" }),
              let names = try? fm.contentsOfDirectory(atPath: examples) else { return }
        for name in names where !fm.fileExists(atPath: folder + "/" + name) {
            try? fm.copyItem(atPath: examples + "/" + name, toPath: folder + "/" + name)
        }
    }

    static func openFolder() {
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        NSWorkspace.shared.open(URL(fileURLWithPath: folder))
    }
}
