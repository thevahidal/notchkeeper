import AppKit

// Brings the session's pane to the front, or its app when Notchkeeper can't pick the pane.
// Exact panes: tmux, WezTerm, kitty (by pane id), and Ghostty, iTerm2, Terminal (by tty over AppleScript).
enum Jump {
    // $TERM_PROGRAM → bundle id.
    private static let terminals = [
        "ghostty": "com.mitchellh.ghostty",
        "iTerm.app": "com.googlecode.iterm2",
        "Apple_Terminal": "com.apple.Terminal",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "WezTerm": "com.github.wez.wezterm",
        "vscode": "com.microsoft.VSCode",
    ]
    private static let scriptable: Set = ["ghostty", "iTerm.app", "Apple_Terminal"]

    static func canReply(_ session: Session) -> Bool {
        session.tty != nil && !session.background && (session.pane != nil || scriptable.contains(session.term ?? ""))
    }

    // The app the session runs in, if known: the desktop app, its terminal, or the app its environment names.
    static func appId(_ session: Session) -> String? {
        if session.tty == nil { return "com.anthropic.claudefordesktop" }
        return session.term.flatMap { terminals[$0] } ?? session.app
    }

    static func to(_ session: Session) {
        guard let tty = session.tty else { return appId(session).map(activate) ?? () }
        if let pane = session.pane {
            focus(pane)
        } else if canReply(session) {
            switch session.term {
            case "ghostty": script(ghostty(tty, "focus t\nactivate"))
            case "iTerm.app": script(iTerm(tty, "select w\nselect t\nselect s\nactivate"))
            default: script(terminal(tty, "set selected of t to true\nset index of w to 1\nactivate"))
            }
            return
        }
        appId(session).map(activate)
    }

    // Types the text into the session's pane, then presses Enter.
    // Returns false without typing when the agent isn't what's running there.
    static func reply(_ session: Session, _ text: String) -> Bool {
        guard let tty = session.tty, canReply(session), agentInForeground(tty, session.agent) else { return false }
        let line = text.components(separatedBy: .newlines).joined(separator: " ")
        if let pane = session.pane { return type(line, into: pane) }
        let quoted = "\"" + line.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        switch session.term {
        case "ghostty": script(ghostty(tty, "input text \(quoted) to t\nsend key \"enter\" to t"))
        case "iTerm.app": script(iTerm(tty, "tell s to write text \(quoted)"))
        default: script(terminal(tty, "do script \(quoted) in t"))
        }
        return true
    }

    private static func focus(_ pane: Pane) {
        switch pane {
        case let .tmux(socket, id):
            guard let tmux = tool("tmux") else { return }
            ClaudeCLI.run(tmux, ["-S", socket, "select-window", "-t", id, ";", "select-pane", "-t", id])
        case let .wezterm(id):
            guard let wezterm = bundled("com.github.wez.wezterm", "wezterm") else { return }
            ClaudeCLI.run(wezterm, ["cli", "activate-pane", "--pane-id", id])
        case let .kitty(socket, id):
            guard let kitten = bundled("net.kovidgoyal.kitty", "kitten") else { return }
            ClaudeCLI.run(kitten, ["@", "--to", socket, "focus-window", "--match", "id:" + id])
        }
    }

    // Arguments go straight to the tool, no shell; `--` / `-l` keep the text from being read as options or key names.
    private static func type(_ text: String, into pane: Pane) -> Bool {
        switch pane {
        case let .tmux(socket, id):
            guard let tmux = tool("tmux") else { return false }
            ClaudeCLI.run(tmux, ["-S", socket, "send-keys", "-t", id, "-l", "--", text])
            ClaudeCLI.run(tmux, ["-S", socket, "send-keys", "-t", id, "Enter"])
        case let .wezterm(id):
            guard let wezterm = bundled("com.github.wez.wezterm", "wezterm") else { return false }
            ClaudeCLI.run(wezterm, ["cli", "send-text", "--pane-id", id, "--no-paste", "--", text + "\r"])
        case let .kitty(socket, id):
            guard let kitten = bundled("net.kovidgoyal.kitty", "kitten") else { return false }
            ClaudeCLI.run(kitten, ["@", "--to", socket, "send-text", "--match", "id:" + id, "--", text])
            ClaudeCLI.run(kitten, ["@", "--to", socket, "send-key", "--match", "id:" + id, "enter"])
        }
        return true
    }

    private static func tool(_ name: String) -> String? {
        ["/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/"].map { $0 + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func bundled(_ bundleId: String, _ binary: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)?.appendingPathComponent("Contents/MacOS/" + binary).path
    }

    // If the agent has exited, the pane is a plain shell and Enter would run the reply as a command.
    private static func agentInForeground(_ tty: String, _ agent: String?) -> Bool {
        // Codex and Gemini ship as Node scripts too, so their process may just be "node".
        let names = agent == nil ? ["claude"] : [agent!, "node"]
        let (_, out) = ClaudeCLI.run("/bin/ps", ["-t", tty, "-o", "stat=,comm="])
        // "+" marks the foreground process group.
        return out.split(separator: "\n").contains { line in
            line.split(separator: " ").first?.contains("+") == true && names.contains { line.hasSuffix($0) }
        }
    }

    // True when the session's pane is the one in front.
    static func isFrontmost(_ session: Session) -> Bool {
        // Checked first so the script never launches the terminal.
        guard let tty = session.tty, session.pane == nil, canReply(session), let id = appId(session),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == id else { return false }
        let query = switch session.term {
        case "ghostty": "tty of focused terminal of selected tab of front window"
        case "iTerm.app": "tty of current session of current window"
        default: "tty of selected tab of front window"
        }
        let script = "tell application id \"\(id)\" to get \(query)"
        return NSAppleScript(source: script)?.executeAndReturnError(nil).stringValue == "/dev/\(tty)"
    }

    private static func ghostty(_ tty: String, _ body: String) -> String {
        """
        tell application id "com.mitchellh.ghostty"
            set t to first terminal whose tty is "/dev/\(tty)"
            \(body)
        end tell
        """
    }

    private static func iTerm(_ tty: String, _ body: String) -> String {
        """
        tell application id "com.googlecode.iterm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "/dev/\(tty)" then
                            \(body)
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
    }

    private static func terminal(_ tty: String, _ body: String) -> String {
        """
        tell application id "com.apple.Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "/dev/\(tty)" then
                        \(body)
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
    }

    private static func script(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("Notchkeeper terminal script failed: \(error)") }
    }

    private static func activate(_ bundleId: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.activate()
    }
}
