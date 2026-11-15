import Foundation

// The coding agents Notchkeeper can hook into, and where each keeps its hooks.
enum Agent: String, CaseIterable {
    case claude, codex, gemini

    var title: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini CLI"
        }
    }

    // The file holding a top-level "hooks" object; all three use the same shape.
    var settingsPath: String {
        switch self {
        case .claude: HookInstaller.home + "/.claude/settings.json"
        case .codex: HookInstaller.home + "/.codex/hooks.json"
        case .gemini: HookInstaller.home + "/.gemini/settings.json"
        }
    }

    // Installed if its config folder exists.
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: (settingsPath as NSString).deletingLastPathComponent)
    }

    fileprivate var toolEvents: [String] { self == .gemini ? ["BeforeTool", "AfterTool"] : ["PreToolUse", "PostToolUse"] }

    fileprivate var otherEvents: [String] {
        switch self {
        case .claude: ["UserPromptSubmit", "Notification", "Stop", "SessionEnd", "SubagentStart", "SubagentStop"]
        case .codex: ["UserPromptSubmit", "Stop", "SessionEnd", "SubagentStart", "SubagentStop"]
        case .gemini: ["BeforeAgent", "AfterAgent", "Notification", "SessionEnd"]
        }
    }

    // Gemini has no event a hook can answer, so it gets status only.
    fileprivate var answersApprovals: Bool { self != .gemini }

    // Gemini counts hook timeouts in milliseconds, the others in seconds.
    fileprivate var timeoutUnit: Int { self == .gemini ? 1000 : 1 }

    fileprivate var hookArgument: String { self == .claude ? "" : " " + rawValue }
}

// Adds or removes Notchkeeper's hooks in each agent's settings. Claude's file is shared by the CLI and desktop app.
// Only Notchkeeper's own entries are touched, and a backup is written next to the file first.
enum HookInstaller {
    // $HOME first, like the hook scripts, so a test with a fake HOME can't touch the real settings.
    static let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    static let hooksDir = home + "/.notchkeeper/hooks"
    // How settings refer to the scripts; the agents run hooks through a shell, which expands the ~.
    private static let hooksRef = "~/.notchkeeper/hooks/"
    private static let scripts = ["notchkeeper-hook.sh", "notchkeeper-approve.sh"]
    // From before the rename; connecting or disconnecting removes them too.
    private static let legacyScripts = ["ping-hook.sh", "ping-approve.sh"]
    private static let legacyDir = home + "/.ping"

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    private static func commands(_ agent: Agent) -> [String] {
        let hooks = (try? load(agent))?["hooks"] as? [String: Any] ?? [:]
        return hooks.values.flatMap { groups in
            (groups as? [[String: Any]] ?? []).flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        }
    }

    static func isConnected(_ agent: Agent = .claude) -> Bool {
        commands(agent).contains(hooksRef + "notchkeeper-hook.sh" + agent.hookArgument)
            && FileManager.default.fileExists(atPath: hooksDir + "/notchkeeper-hook.sh")
    }

    // Still wired up under the app's old name, Ping.
    static var hasLegacyHooks: Bool {
        commands(.claude).contains { $0.hasSuffix("/ping-approve.sh") }
    }

    static func connect(_ agent: Agent = .claude) throws {
        try copyScripts()
        try edit(agent) { hooks in
            func add(_ event: String, _ script: String, matcher: String? = nil, timeout: Int = 10) {
                let hook: [String: Any] = ["type": "command", "command": hooksRef + script + agent.hookArgument,
                                           "timeout": timeout * agent.timeoutUnit]
                var group: [String: Any] = ["hooks": [hook]]
                if let matcher { group["matcher"] = matcher }
                hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [group]
            }
            agent.toolEvents.forEach { add($0, "notchkeeper-hook.sh", matcher: "*") }
            agent.otherEvents.forEach { add($0, "notchkeeper-hook.sh") }
            // Longer than the script's own 30s wait, so the agent never kills it mid-answer.
            if agent.answersApprovals { add("PermissionRequest", "notchkeeper-approve.sh", matcher: "*", timeout: 40) }
        }
        if agent == .claude { removeLegacyFiles() }
    }

    static func disconnect(_ agent: Agent = .claude) throws {
        try edit(agent) { _ in }
        if agent == .claude { removeLegacyFiles() }
        if !Agent.allCases.contains(where: { isConnected($0) }) { try? FileManager.default.removeItem(atPath: hooksDir) }
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
        if Agent.allCases.contains(where: { isConnected($0) }) { try? copyScripts() }
    }

    // Hooks run on every agent event, so they run from a private copy, not from inside the app bundle.
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

    private static func load(_ agent: Agent) throws -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: agent.settingsPath) else { return [:] }
        // Never overwrite a settings file we can't read; that would lose the user's settings.
        guard let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let shown = agent.settingsPath.replacingOccurrences(of: home, with: "~")
            throw Failure(errorDescription: "\(shown) isn't valid JSON, so Notchkeeper left it alone")
        }
        return settings
    }

    // Removes Notchkeeper's entries, lets `change` add new ones, then writes the file back.
    private static func edit(_ agent: Agent, _ change: (inout [String: Any]) -> Void) throws {
        let path = agent.settingsPath
        var settings = try load(agent)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, value) in hooks {
            let groups = (value as? [[String: Any]] ?? []).compactMap { group -> [String: Any]? in
                var group = group
                let kept = (group["hooks"] as? [[String: Any]] ?? []).filter { hook in
                    let command = hook["command"] as? String ?? ""
                    return !command.contains("/.notchkeeper/hooks/") && !legacyScripts.contains { command.hasSuffix("/" + $0) }
                }
                group["hooks"] = kept
                return kept.isEmpty ? nil : group
            }
            hooks[event] = groups.isEmpty ? nil : groups
        }
        change(&hooks)
        settings["hooks"] = hooks.isEmpty ? nil : hooks

        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            let stamp = String(Int(Date().timeIntervalSince1970 * 1000))
            try fm.copyItem(atPath: path, toPath: path + ".notchkeeper-backup-" + stamp)
        }
        try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (data + Data("\n".utf8)).write(to: URL(fileURLWithPath: path), options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
}
