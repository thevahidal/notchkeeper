import AppKit

// Brings the session's terminal pane to the front, or the desktop app when it has no terminal.
// Ghostty, iTerm2 and Terminal.app expose each pane's tty to AppleScript; other terminals just come forward.
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
        session.tty != nil && !session.background && scriptable.contains(session.term ?? "")
    }

    // The app the session runs in, if known: the desktop app, or the terminal for CLI sessions.
    static func appId(_ session: Session) -> String? {
        if session.tty == nil { return "com.anthropic.claudefordesktop" }
        return session.term.flatMap { terminals[$0] }
    }

    static func to(_ session: Session) {
        guard let tty = session.tty, canReply(session) else { return appId(session).map(activate) ?? () }
        switch session.term {
        case "ghostty": run(ghostty(tty, "focus t\nactivate"))
        case "iTerm.app": run(iTerm(tty, "select w\nselect t\nselect s\nactivate"))
        default: run(terminal(tty, "set selected of t to true\nset index of w to 1\nactivate"))
        }
    }

    // Types the text into the session's pane, then presses Enter.
    // Returns false without typing when Claude isn't what's running there.
    static func reply(_ session: Session, _ text: String) -> Bool {
        guard let tty = session.tty, canReply(session), claudeInForeground(tty) else { return false }
        let line = text.components(separatedBy: .newlines).joined(separator: " ")
        let quoted = "\"" + line.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        switch session.term {
        case "ghostty": run(ghostty(tty, "input text \(quoted) to t\nsend key \"enter\" to t"))
        case "iTerm.app": run(iTerm(tty, "tell s to write text \(quoted)"))
        default: run(terminal(tty, "do script \(quoted) in t"))
        }
        return true
    }

    // If Claude has exited, the tab is a plain shell and Enter would run the reply as a command.
    private static func claudeInForeground(_ tty: String) -> Bool {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-t", tty, "-o", "stat=,comm="]
        let out = Pipe()
        ps.standardOutput = out
        guard (try? ps.run()) != nil else { return false }
        ps.waitUntilExit()
        let lines = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n")
        // "+" marks the foreground process group.
        return lines.contains { $0.split(separator: " ").first?.contains("+") == true && $0.hasSuffix("claude") }
    }

    // True when the session's pane is the one in front.
    static func isFrontmost(_ session: Session) -> Bool {
        // Checked first so the script never launches the terminal.
        guard let tty = session.tty, canReply(session), let id = appId(session),
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

    private static func run(_ script: String) {
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error { NSLog("Notchkeeper terminal script failed: \(error)") }
    }

    private static func activate(_ bundleId: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.activate()
    }
}
