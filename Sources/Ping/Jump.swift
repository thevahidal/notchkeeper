import AppKit

// Brings the session's terminal pane to the front, or the desktop app when it has no terminal.
enum Jump {
    static func canReply(_ session: Session) -> Bool {
        session.tty != nil && session.term == "ghostty"
    }

    // The app the session runs in, if known: the desktop app, or the terminal for CLI sessions.
    static func appId(_ session: Session) -> String? {
        if session.tty == nil { return "com.anthropic.claudefordesktop" }
        return session.term == "ghostty" ? "com.mitchellh.ghostty" : nil
    }

    static func to(_ session: Session) {
        guard let tty = session.tty else { return activate(appId(session)!) }
        guard session.term == "ghostty" else { return }
        run(tty, "focus t\nactivate")
    }

    // Types the text into the session's pane as if pasted, then presses Enter.
    // Returns false without typing when Claude isn't what's running there.
    static func reply(_ session: Session, _ text: String) -> Bool {
        guard let tty = session.tty, canReply(session), claudeInForeground(tty) else { return false }
        let line = text.components(separatedBy: .newlines).joined(separator: " ")
        let quoted = line.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        run(tty, "input text \"\(quoted)\" to t\nsend key \"enter\" to t")
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

    // True when the session's Ghostty pane is the one in front.
    static func isFrontmost(_ session: Session) -> Bool {
        // Checked first so the script never launches Ghostty.
        guard let tty = session.tty, canReply(session),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == appId(session) else { return false }
        let script = "tell application \"Ghostty\" to get tty of focused terminal of selected tab of front window"
        return NSAppleScript(source: script)?.executeAndReturnError(nil).stringValue == "/dev/\(tty)"
    }

    private static func run(_ tty: String, _ body: String) {
        let script = """
            tell application "Ghostty"
                set t to first terminal whose tty is "/dev/\(tty)"
                \(body)
            end tell
            """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error { NSLog("Ping Ghostty script failed: \(error)") }
    }

    private static func activate(_ bundleId: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.activate()
    }
}
