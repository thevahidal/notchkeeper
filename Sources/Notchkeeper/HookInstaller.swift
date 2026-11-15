import Foundation

// Adds or removes Notchkeeper's hooks in ~/.claude/settings.json, which the Claude Code CLI and desktop app share.
// Only Notchkeeper's own entries are touched, and a backup is written next to the file first.
enum HookInstaller {
    // $HOME first, like the hook scripts, so a test with a fake HOME can't touch the real settings.
    private static let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    static let settingsPath = home + "/.claude/settings.json"
    static let hooksDir = home + "/.notchkeeper/hooks"
    // How settings.json refers to the scripts; Claude expands the ~.
    private static let hooksRef = "~/.notchkeeper/hooks/"
    private static let scripts = ["notchkeeper-hook.sh", "notchkeeper-approve.sh"]
    // From before the rename; connecting or disconnecting removes them too.
    private static let legacyScripts = ["ping-hook.sh", "ping-approve.sh"]
    private static let legacyDir = home + "/.ping"
    private static let toolEvents = ["PreToolUse", "PostToolUse"]
    private static let otherEvents = ["UserPromptSubmit", "Notification", "Stop", "SessionEnd", "SubagentStart", "SubagentStop"]

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    private static var commands: [String] {
        let hooks = (try? load())?["hooks"] as? [String: Any] ?? [:]
        return hooks.values.flatMap { groups in
            (groups as? [[String: Any]] ?? []).flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        }
    }

    static var isConnected: Bool {
        commands.contains(hooksRef + "notchkeeper-approve.sh") && FileManager.default.fileExists(atPath: hooksDir + "/notchkeeper-hook.sh")
    }

    // Still wired up under the app's old name, Ping.
    static var hasLegacyHooks: Bool {
        commands.contains { $0.hasSuffix("/ping-approve.sh") }
    }

    static func connect() throws {
        try copyScripts()
        try edit { hooks in
            func add(_ event: String, _ script: String, matcher: String? = nil, timeout: Int? = nil) {
                var hook: [String: Any] = ["type": "command", "command": hooksRef + script]
                if let timeout { hook["timeout"] = timeout }
                var group: [String: Any] = ["hooks": [hook]]
                if let matcher { group["matcher"] = matcher }
                hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [group]
            }
            toolEvents.forEach { add($0, "notchkeeper-hook.sh", matcher: "*") }
            otherEvents.forEach { add($0, "notchkeeper-hook.sh") }
            // Longer than the script's own 30s wait, so Claude never kills it mid-answer.
            add("PermissionRequest", "notchkeeper-approve.sh", matcher: "*", timeout: 40)
        }
        removeLegacyFiles()
    }

    static func disconnect() throws {
        try edit { _ in }
        try? FileManager.default.removeItem(atPath: hooksDir)
        removeLegacyFiles()
    }

    // Ping's old hook copies and socket; the folder goes too once it's empty.
    private static func removeLegacyFiles() {
        let fm = FileManager.default
        try? fm.removeItem(atPath: legacyDir + "/hooks")
        try? fm.removeItem(atPath: legacyDir + "/ping.sock")
        if (try? fm.contentsOfDirectory(atPath: legacyDir))?.isEmpty == true { try? fm.removeItem(atPath: legacyDir) }
    }

    // A new version of the app may ship new scripts; keep an existing install's copies current.
    static func refreshScripts() {
        if isConnected { try? copyScripts() }
    }

    // Hooks run on every Claude event, so they run from a private copy, not from inside the app bundle.
    private static func copyScripts() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: hooksDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for name in scripts {
            guard let source = Bundle.main.path(forResource: name, ofType: nil, inDirectory: "hooks") else {
                throw Failure(errorDescription: "\(name) is missing from the app bundle")
            }
            let target = hooksDir + "/" + name
            try? fm.removeItem(atPath: target)
            try fm.copyItem(atPath: source, toPath: target)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: target)
        }
    }

    private static func load() throws -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: settingsPath) else { return [:] }
        // Never overwrite a settings file we can't read; that would lose the user's settings.
        guard let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(errorDescription: "~/.claude/settings.json isn't valid JSON, so Notchkeeper left it alone")
        }
        return settings
    }

    // Removes Notchkeeper's entries, lets `change` add new ones, then writes the file back.
    private static func edit(_ change: (inout [String: Any]) -> Void) throws {
        var settings = try load()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, value) in hooks {
            let groups = (value as? [[String: Any]] ?? []).compactMap { group -> [String: Any]? in
                var group = group
                let kept = (group["hooks"] as? [[String: Any]] ?? []).filter { hook in
                    let command = hook["command"] as? String ?? ""
                    return !(scripts + legacyScripts).contains { command.hasSuffix("/" + $0) }
                }
                group["hooks"] = kept
                return kept.isEmpty ? nil : group
            }
            hooks[event] = groups.isEmpty ? nil : groups
        }
        change(&hooks)
        settings["hooks"] = hooks.isEmpty ? nil : hooks

        let fm = FileManager.default
        if fm.fileExists(atPath: settingsPath) {
            let stamp = String(Int(Date().timeIntervalSince1970 * 1000))
            try fm.copyItem(atPath: settingsPath, toPath: settingsPath + ".notchkeeper-backup-" + stamp)
        }
        try fm.createDirectory(atPath: (settingsPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (data + Data("\n".utf8)).write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsPath)
    }
}
