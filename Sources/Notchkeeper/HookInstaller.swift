import Foundation

// The coding agents Notchkeeper can hook into. Everything that differs between them is in `spec`.
enum Agent: String, CaseIterable {
    case claude, codex, gemini, cursor, copilot, droid, kiro, opencode, vibe

    // How one hook entry is written in the agent's file.
    enum Layout {
        // Claude's: event → [{matcher, hooks: [{type, command, timeout}]}].
        case groups
        // Cursor's: {version: 1, hooks: {event → [{command, timeout}]}}.
        case flat
        // A file of Notchkeeper's own: Copilot's {version: 1, hooks: {event → [{type, bash, timeoutSec}]}}.
        case copilot
        // A file of Notchkeeper's own: Kiro's {version: "v1", hooks: [{name, trigger, matcher, action, timeout}]}.
        case kiro
        // A file of Notchkeeper's own: the bundled OpenCode plugin, which sends Claude-named events itself.
        case opencode
        // A marked block of [[hooks]] tables in Vibe's hooks.toml.
        case vibe
    }

    struct Spec {
        let title: String
        // Under $HOME.
        let settingsFile: String
        var layout = Layout.groups
        // The agent's event names → Claude Code's, which the rest of the app uses.
        let events: [String: String]
        var answersApprovals = false
        // Seconds per timeout unit the agent counts in.
        var timeoutUnit = 1
        // Shown in Settings once connected.
        let note: String
        // Shown once after connecting, when the agent needs a step of its own.
        var connectHint: String? = nil
        // The agent's process name, when it isn't the raw value.
        var process: String? = nil
        // Under $HOME; its existence means the agent is installed. Defaults to the first folder of settingsFile.
        var configFolder: String? = nil
    }

    // New agents skip "before tool" events: a hook that fails there blocks the tool in Cursor, Copilot and Kiro.
    var spec: Spec {
        switch self {
        case .claude: Spec(
            title: "Claude Code", settingsFile: ".claude/settings.json",
            events: Self.same(["PreToolUse", "PostToolUse", "UserPromptSubmit", "Notification", "Stop", "SessionEnd", "SubagentStart", "SubagentStop"]),
            answersApprovals: true, note: "status and approvals")
        case .codex: Spec(
            title: "Codex", settingsFile: ".codex/hooks.json",
            events: Self.same(["PreToolUse", "PostToolUse", "UserPromptSubmit", "Stop", "SessionEnd", "SubagentStart", "SubagentStop"]),
            answersApprovals: true, note: "approve the hooks in Codex with /hooks",
            connectHint: "Open Codex and approve Notchkeeper's hooks with /hooks. Until then Codex won't run them.")
        case .gemini: Spec(
            title: "Gemini CLI", settingsFile: ".gemini/settings.json",
            events: ["BeforeTool": "PreToolUse", "AfterTool": "PostToolUse", "BeforeAgent": "UserPromptSubmit",
                     "AfterAgent": "Stop", "Notification": "Notification", "SessionEnd": "SessionEnd"],
            // Gemini counts timeouts in milliseconds.
            timeoutUnit: 1000, note: "status only, approvals stay in Gemini")
        case .cursor: Spec(
            title: "Cursor", settingsFile: ".cursor/hooks.json", layout: .flat,
            events: ["beforeSubmitPrompt": "UserPromptSubmit", "postToolUse": "PostToolUse", "stop": "Stop", "sessionEnd": "SessionEnd"],
            note: "status only, approvals stay in Cursor", process: "cursor-agent")
        case .copilot: Spec(
            title: "Copilot CLI", settingsFile: ".copilot/hooks/notchkeeper.json", layout: .copilot,
            // Copilot sends Claude's snake_case payload, with hook_event_name, only under the PascalCase names.
            events: Self.same(["UserPromptSubmit", "PostToolUse", "Stop", "SessionEnd"]).merging(["notification": "Notification"]) { a, _ in a },
            note: "status only, approvals stay in Copilot")
        case .droid: Spec(
            title: "Droid", settingsFile: ".factory/settings.json",
            events: Self.same(["PreToolUse", "PostToolUse", "UserPromptSubmit", "Notification", "Stop", "SessionEnd", "SubagentStop"]),
            note: "status only, approvals stay in Droid")
        case .kiro: Spec(
            title: "Kiro CLI", settingsFile: ".kiro/hooks/notchkeeper.json", layout: .kiro,
            events: Self.same(["UserPromptSubmit", "PostToolUse", "Stop", "SessionEnd"]),
            note: "status only, approvals stay in Kiro", process: "kiro-cli")
        case .opencode: Spec(
            title: "OpenCode", settingsFile: ".config/opencode/plugins/notchkeeper.js", layout: .opencode,
            events: [:], note: "status only, approvals stay in OpenCode", configFolder: ".config/opencode")
        case .vibe: Spec(
            title: "Mistral Vibe", settingsFile: ".vibe/hooks.toml", layout: .vibe,
            // Vibe's docs don't say what hook_event_name holds; Claude's names would pass through unchanged.
            events: ["post_tool": "PostToolUse", "post_agent": "Stop"],
            note: "status only, approvals stay in Vibe")
        }
    }

    private static func same(_ names: [String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: names.map { ($0, $0) })
    }

    var title: String { spec.title }
    var settingsPath: String { HookInstaller.home + "/" + spec.settingsFile }
    var process: String { spec.process ?? rawValue }

    var isInstalled: Bool {
        let folder = spec.configFolder ?? spec.settingsFile.split(separator: "/").first.map(String.init) ?? ""
        return FileManager.default.fileExists(atPath: HookInstaller.home + "/" + folder)
    }

    // An event in the agent's own names and fields, renamed to Claude Code's.
    func normalize(_ event: [String: Any]) -> [String: Any] {
        var event = event
        if let name = event["hook_event_name"] as? String, let mapped = spec.events[name] { event["hook_event_name"] = mapped }
        // Gemini's name for the reply.
        if let response = event["prompt_response"] as? String { event["last_assistant_message"] = response }
        // Cursor names the session conversation_id and gives workspace folders; Copilot uses camelCase.
        event["session_id"] = event["session_id"] ?? event["sessionId"] ?? event["conversation_id"]
        event["cwd"] = event["cwd"] ?? (event["workspace_roots"] as? [String])?.first
        event["tool_name"] = event["tool_name"] ?? event["toolName"]
        if event["tool_input"] == nil, let args = event["toolArgs"] {
            event["tool_input"] = (args as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } ?? args
        }
        return event
    }

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
    private static let blockStart = "# >>> notchkeeper: added by Notchkeeper, disconnecting removes this block"
    private static let blockEnd = "# <<< notchkeeper"

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    // Droid reads ~/.factory/hooks.json, which is the hooks object itself, when it exists; settings.json's "hooks" otherwise.
    private static func location(_ agent: Agent) -> (path: String, atRoot: Bool) {
        let droidHooks = home + "/.factory/hooks.json"
        if agent == .droid && FileManager.default.fileExists(atPath: droidHooks) { return (droidHooks, true) }
        return (agent.settingsPath, false)
    }

    private static func commands(_ agent: Agent) -> [String] {
        let (path, atRoot) = location(agent)
        let settings = (try? load(path)) ?? [:]
        return strings(atRoot ? settings : settings["hooks"] ?? [:])
    }

    // Every command in a hooks value, whatever its layout.
    private static func strings(_ value: Any) -> [String] {
        if let list = value as? [Any] { return list.flatMap(strings) }
        guard let object = value as? [String: Any] else { return [] }
        return object.flatMap { key, value in
            (key == "command" || key == "bash") ? [value as? String].compactMap { $0 } : strings(value)
        }
    }

    private static func isOurs(_ hook: [String: Any]) -> Bool {
        let command = hook["command"] as? String ?? ""
        return command.contains("/.notchkeeper/hooks/") || legacyScripts.contains { command.hasSuffix("/" + $0) }
    }

    static func isConnected(_ agent: Agent = .claude) -> Bool {
        let wired: Bool
        switch agent.spec.layout {
        case .opencode, .vibe:
            wired = (try? String(contentsOfFile: agent.settingsPath, encoding: .utf8))?.contains("notchkeeper-hook.sh") == true
        default:
            wired = commands(agent).contains(hooksRef + "notchkeeper-hook.sh" + agent.hookArgument)
        }
        return wired && FileManager.default.fileExists(atPath: hooksDir + "/notchkeeper-hook.sh")
    }

    // Still wired up under the app's old name, Ping.
    static var hasLegacyHooks: Bool {
        commands(.claude).contains { $0.hasSuffix("/ping-approve.sh") }
    }

    static func connect(_ agent: Agent = .claude) throws {
        try copyScripts()
        let command = hooksRef + "notchkeeper-hook.sh" + agent.hookArgument
        func isTool(_ event: String) -> Bool { ["PreToolUse", "PostToolUse"].contains(agent.spec.events[event]) }
        let events = agent.spec.events.keys.sorted()

        switch agent.spec.layout {
        case .copilot:
            let hooks = Dictionary(uniqueKeysWithValues: events.map { ($0, [["type": "command", "bash": command, "timeoutSec": 10]]) })
            try write(["version": 1, "hooks": hooks], to: agent.settingsPath, backup: false)
        case .kiro:
            let hooks: [[String: Any]] = events.map { event in
                var hook: [String: Any] = ["name": "notchkeeper-" + event, "trigger": event, "timeout": 10,
                                           "action": ["type": "command", "command": command]]
                if isTool(event) { hook["matcher"] = "*" }
                return hook
            }
            try write(["version": "v1", "hooks": hooks], to: agent.settingsPath, backup: false)
        case .opencode:
            guard let source = Bundle.main.path(forResource: "notchkeeper-opencode.js", ofType: nil, inDirectory: "hooks") else {
                throw Failure(errorDescription: "notchkeeper-opencode.js is missing from the app bundle")
            }
            try write(try Data(contentsOf: URL(fileURLWithPath: source)), to: agent.settingsPath, backup: false)
        case .vibe:
            // Vibe may run the command without a shell, so no ~; TOML strings escape \ and ".
            let absolute = (hooksDir + "/notchkeeper-hook.sh vibe").replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let tables = events.map { event in
                "[[hooks]]\nname = \"notchkeeper-\(event)\"\ntype = \"\(event)\"\nmatch = \"\(isTool(event) ? "*" : "main")\"\n"
                    + "command = \"\(absolute)\"\ntimeout = 10.0\n"
            }
            try editBlock(agent, ([blockStart] + tables + [blockEnd]).joined(separator: "\n"))
        case .groups, .flat:
            try edit(agent) { hooks in
                func add(_ event: String, _ command: String, matcher: String? = nil, timeout: Int = 10) {
                    let entry: [String: Any]
                    if agent.spec.layout == .flat {
                        entry = ["command": command, "timeout": timeout]
                    } else {
                        let hook: [String: Any] = ["type": "command", "command": command, "timeout": timeout * agent.spec.timeoutUnit]
                        var group: [String: Any] = ["hooks": [hook]]
                        if let matcher { group["matcher"] = matcher }
                        entry = group
                    }
                    hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [entry]
                }
                for event in events { add(event, command, matcher: isTool(event) ? "*" : nil) }
                // Longer than the script's own 30s wait, so the agent never kills it mid-answer.
                if agent.spec.answersApprovals {
                    add("PermissionRequest", hooksRef + "notchkeeper-approve.sh" + agent.hookArgument, matcher: "*", timeout: 40)
                }
            }
        }
        if agent == .claude { removeLegacyFiles() }
    }

    static func disconnect(_ agent: Agent = .claude) throws {
        switch agent.spec.layout {
        case .copilot, .kiro, .opencode:
            if FileManager.default.fileExists(atPath: agent.settingsPath) { try FileManager.default.removeItem(atPath: agent.settingsPath) }
        case .vibe:
            try editBlock(agent, nil)
        case .groups, .flat:
            try edit(agent) { _ in }
        }
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

    private static func load(_ path: String) throws -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: path) else { return [:] }
        // Never overwrite a settings file we can't read; that would lose the user's settings.
        guard let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let shown = path.replacingOccurrences(of: home, with: "~")
            throw Failure(errorDescription: "\(shown) isn't valid JSON, so Notchkeeper left it alone")
        }
        return settings
    }

    // Removes Notchkeeper's entries, lets `change` add new ones, then writes the file back.
    private static func edit(_ agent: Agent, _ change: (inout [String: Any]) -> Void) throws {
        let (path, atRoot) = location(agent)
        var settings = try load(path)
        var hooks = (atRoot ? settings : settings["hooks"] as? [String: Any]) ?? [:]
        for (event, value) in hooks {
            let kept = (value as? [[String: Any]] ?? []).compactMap { item -> [String: Any]? in
                // A Cursor entry is the hook itself; a Claude-style group holds a list of them.
                guard var inner = item["hooks"] as? [[String: Any]] else { return isOurs(item) ? nil : item }
                inner.removeAll(where: isOurs)
                var group = item
                group["hooks"] = inner
                return inner.isEmpty ? nil : group
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        change(&hooks)
        if atRoot {
            settings = hooks
        } else {
            settings["hooks"] = hooks.isEmpty ? nil : hooks
            if agent.spec.layout == .flat && settings["version"] == nil { settings["version"] = 1 }
        }
        try write(settings, to: path)
    }

    // Replaces Notchkeeper's marked block in a text config (or removes it when `block` is nil).
    private static func editBlock(_ agent: Agent, _ block: String?) throws {
        let path = agent.settingsPath
        if block == nil && !FileManager.default.fileExists(atPath: path) { return }
        var text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        if let start = text.range(of: blockStart), let end = text.range(of: blockEnd, range: start.upperBound..<text.endIndex) {
            text.removeSubrange(start.lowerBound..<end.upperBound)
        }
        while text.hasSuffix("\n") { text.removeLast() }
        if let block { text += (text.isEmpty ? "" : "\n\n") + block }
        if !text.isEmpty { text += "\n" }
        try write(Data(text.utf8), to: path)
    }

    private static func write(_ settings: [String: Any], to path: String, backup: Bool = true) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try write(data + Data("\n".utf8), to: path, backup: backup)
    }

    private static func write(_ data: Data, to path: String, backup: Bool = true) throws {
        let fm = FileManager.default
        if backup && fm.fileExists(atPath: path) {
            let stamp = String(Int(Date().timeIntervalSince1970 * 1000))
            try fm.copyItem(atPath: path, toPath: path + ".notchkeeper-backup-" + stamp)
        }
        try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
}
