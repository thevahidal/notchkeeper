import AppKit
import CryptoKit

// Plugins: folders in ~/.notchkeeper/plugins, each with a plugin.json and a script.
// Notchkeeper runs a plugin's script when one of its events happens, with the event as JSON on stdin.
// Off until you turn each one on; scripts run directly (no shell) and only from inside their own folder.
struct Plugin: Identifiable {
    let id: String
    let name: String
    let description: String
    let executable: String
    let events: Set<String>
    let settings: [PluginSetting]
}

// One entry of a plugin.json's "settings": text, toggle or choice, always with a usable default.
struct PluginSetting {
    let key: String
    let title: String
    let type: String
    let options: [String]
    let defaultValue: Any

    init?(_ entry: [String: Any]) {
        guard let key = entry["key"] as? String, !key.isEmpty, let type = entry["type"] as? String else { return nil }
        let options = entry["options"] as? [String] ?? []
        let fallback: Any?
        switch type {
        case "text": fallback = ""
        case "toggle": fallback = false
        case "choice": fallback = options.first
        default: return nil
        }
        guard let value = Self.clean(entry["default"], type, options) ?? Self.clean(fallback, type, options) else { return nil }
        (self.key, self.type, self.options, defaultValue) = (key, type, options, value)
        title = entry["title"] as? String ?? key
    }

    func clean(_ value: Any?) -> Any? { Self.clean(value, type, options) }

    private static func clean(_ value: Any?, _ type: String, _ options: [String]) -> Any? {
        switch type {
        case "text": return (value as? String).map { String($0.prefix(500)) }
        case "toggle": return value as? Bool
        case "choice": return (value as? String).flatMap { options.contains($0) ? $0 : nil }
        default: return nil
        }
    }
}

enum Plugins {
    static let folder = HookInstaller.home + "/.notchkeeper/plugins"
    static let events = ["needs-you", "done", "approval", "prompt", "reply", "tick"]
    // Kept outside the plugin folders, so replacing a plugin keeps your settings.
    static let settingsFolder = HookInstaller.home + "/.notchkeeper/plugin-settings"

    // Examples run from inside the app, so they update with it. A folder of yours with the same name wins.
    static let bundled = (Bundle.main.resourcePath ?? "") + "/plugins"

    static var all: [Plugin] {
        var found: [String: Plugin] = [:]
        for plugin in load(bundled) + load(folder) { found[plugin.id] = plugin }
        return found.values.sorted { $0.id < $1.id }
    }

    private static func load(_ root: String) -> [Plugin] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: root)) ?? []
        return names.compactMap { name in
            let dir = (root + "/" + name as NSString).standardizingPath
            guard let data = fm.contents(atPath: dir + "/plugin.json"),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let run = manifest["run"] as? String else { return nil }
            // The script must live inside the plugin's folder.
            let executable = (dir + "/" + run as NSString).standardizingPath
            guard executable.hasPrefix(dir + "/"), fm.isExecutableFile(atPath: executable) else { return nil }
            return Plugin(id: name, name: manifest["name"] as? String ?? name, description: manifest["description"] as? String ?? "",
                          executable: executable, events: Set(manifest["on"] as? [String] ?? []),
                          settings: (manifest["settings"] as? [[String: Any]] ?? []).compactMap(PluginSetting.init))
        }
    }

    static var enabled: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "enabledPlugins") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "enabledPlugins") }
    }

    // The defaults, overridden by whatever you saved that the plugin still declares and is valid.
    static func values(_ plugin: Plugin) -> [String: Any] {
        let stored = storedValues(plugin)
        var result: [String: Any] = [:]
        for setting in plugin.settings { result[setting.key] = setting.clean(stored[setting.key]) ?? setting.defaultValue }
        return result
    }

    static func save(_ plugin: Plugin, _ key: String, _ value: Any) {
        guard let value = plugin.settings.first(where: { $0.key == key })?.clean(value) else { return }
        var stored = storedValues(plugin)
        stored[key] = value
        guard let data = try? JSONSerialization.data(withJSONObject: stored, options: [.prettyPrinted, .sortedKeys]) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: settingsFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        fm.createFile(atPath: settingsPath(plugin), contents: data, attributes: [.posixPermissions: 0o600])
    }

    private static func settingsPath(_ plugin: Plugin) -> String { settingsFolder + "/" + plugin.id + ".json" }

    private static func storedValues(_ plugin: Plugin) -> [String: Any] {
        FileManager.default.contents(atPath: settingsPath(plugin))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    // `tick` has no session: it fires every minute for plugins that keep their own time.
    static func emit(_ event: String, _ session: Session?, extra: [String: Any] = [:], reply: @escaping ([String: Any]) -> Void = { _ in }) {
        let targets = all.filter { enabled.contains($0.id) && $0.events.contains(event) }
        guard !targets.isEmpty else { return }
        var payload: [String: Any] = ["event": event]
        if let session {
            payload["session"] = [
                "id": session.id, "title": session.title.isEmpty ? session.repo : session.title, "repo": session.repo,
                "agent": session.agent ?? "claude", "detail": session.question ?? session.detail, "url": session.url ?? "",
            ]
        }
        payload.merge(extra) { $1 }
        for plugin in targets {
            payload["settings"] = values(plugin)
            if let data = try? JSONSerialization.data(withJSONObject: payload) { run(plugin, data, reply) }
        }
    }

    // Each run gets 10 seconds; a hung plugin can't pile up.
    private static func run(_ plugin: Plugin, _ input: Data, _ reply: @escaping ([String: Any]) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: plugin.executable)
        process.currentDirectoryURL = URL(fileURLWithPath: (plugin.executable as NSString).deletingLastPathComponent)
        process.environment = ["HOME": HookInstaller.home, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return NSLog("Notchkeeper: plugin \(plugin.id) didn't start") }
        stdin.fileHandleForWriting.write(input)
        try? stdin.fileHandleForWriting.close()
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { if process.isRunning { process.terminate() } }
        // A reply is one JSON object on stdout, up to 4 KB; anything else is ignored.
        DispatchQueue.global().async {
            let data = stdout.fileHandleForReading.readData(ofLength: 4097)
            try? stdout.fileHandleForReading.close()
            guard data.count <= 4096, let answer = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            DispatchQueue.main.async { reply(answer) }
        }
    }

    // SHA-256 of plugin.json + run.sh for each example as "Add Example Plugins" used to copy it.
    private static let oldExamples = [
        "journal": "8d3b34ae0b69ddfad8bfca1338ea3be8648d22636d9911140d698fa344af88b1",
        "ntfy": "cf35498583dad5d156cca90f0cd24c3aed604171ef33d2e1f10c2a3189e22770",
        "say": "12abecc2cb48c28c99b46e2e7b5ee26651b001fc9955a082f94a74e541981568",
    ]

    // Copies of old examples you never edited go to the Trash, so the bundled ones take over.
    // A <key>.txt in the copy (ntfy's topic.txt) becomes that setting first.
    static func retireOldExamples() {
        let fm = FileManager.default
        for (name, hash) in oldExamples {
            let dir = folder + "/" + name
            guard let files = try? fm.contentsOfDirectory(atPath: dir),
                  Set(files).subtracting(["topic.txt", "server.txt", ".DS_Store"]) == ["plugin.json", "run.sh"],
                  let json = fm.contents(atPath: dir + "/plugin.json"), let run = fm.contents(atPath: dir + "/run.sh"),
                  SHA256.hash(data: json + run).map({ String(format: "%02x", $0) }).joined() == hash,
                  let plugin = load(bundled).first(where: { $0.id == name }) else { continue }
            for setting in plugin.settings where storedValues(plugin)[setting.key] == nil {
                let line = (try? String(contentsOfFile: dir + "/" + setting.key + ".txt"))?
                    .components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
                if !line.isEmpty { save(plugin, setting.key, line) }
            }
            try? fm.trashItem(at: URL(fileURLWithPath: dir), resultingItemURL: nil)
        }
    }

    // `notchkeeper todo …` runs the Backlog plugin's script in your terminal with these arguments.
    static func todo(_ args: [String]) -> Int32 {
        guard let plugin = all.first(where: { $0.id == "backlog" }), enabled.contains(plugin.id) else {
            FileHandle.standardError.write(Data("Turn on the Backlog plugin in Notchkeeper's Settings first.\n".utf8))
            return 2
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: plugin.executable)
        process.arguments = args.isEmpty ? ["list"] : args
        guard (try? process.run()) != nil else { return 1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    static func openFolder() {
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        NSWorkspace.shared.open(URL(fileURLWithPath: folder))
    }
}
