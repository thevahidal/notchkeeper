import AppKit

// Runs the `claude` command: start background agents, tell which sessions are background ones, attach to them.
// Arguments go straight to the process, never through a shell, so a prompt can't run anything.
enum ClaudeCLI {
    // Apps opened from Finder get a bare PATH, so look in the usual install spots, then ask a login shell.
    static let path: String? = {
        let home = NSHomeDirectory()
        let candidates = [home + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", home + "/.claude/local/claude"]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return found }
        let (status, out) = run("/bin/zsh", ["-lc", "command -v claude"], in: nil)
        let line = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return status == 0 && line.hasPrefix("/") ? line : nil
    }()

    // "fix flaky login test" → "fix-flaky-login-test-3f2a"; the suffix keeps worktree names unique.
    static func name(for prompt: String) -> String {
        let words = prompt.lowercased().split { !$0.isLetter && !$0.isNumber }.prefix(4).joined(separator: "-")
        let suffix = String(UUID().uuidString.prefix(4)).lowercased()
        return (words.isEmpty ? "agent" : String(words.prefix(32))) + "-" + suffix
    }

    // `claude --bg` prints "backgrounded · <short id> · <name>"; returns the short id, or the error Claude printed.
    static func launch(prompt: String, in folder: String, worktree: Bool, done: @escaping (Result<String, Failure>) -> Void) {
        guard let path else { return done(.failure(Failure(message: "Couldn't find the claude command."))) }
        let name = name(for: prompt)
        let args = ["--bg", "-n", name] + (worktree ? ["-w", name] : []) + [prompt]
        DispatchQueue.global(qos: .userInitiated).async {
            let (status, out) = run(path, args, in: folder)
            let id = out.range(of: "backgrounded · ([0-9a-f]+)", options: .regularExpression)
                .map { out[$0].components(separatedBy: " · ").last ?? "" }
            let firstLine = out.split(separator: "\n").first.map(String.init) ?? "claude exited with \(status)"
            DispatchQueue.main.async { done(id.map { .success($0) } ?? .failure(Failure(message: firstLine))) }
        }
    }

    // Session ids of running background agents.
    static func backgroundSessions(done: @escaping (Set<String>) -> Void) {
        guard let path else { return }
        DispatchQueue.global(qos: .utility).async {
            let (_, out) = run(path, ["agents", "--json"], in: nil)
            let list = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [[String: Any]] ?? []
            let ids = list.filter { $0["kind"] as? String == "background" }.compactMap { $0["sessionId"] as? String }
            DispatchQueue.main.async { done(Set(ids)) }
        }
    }

    static var attachInNewTab: Bool {
        get { UserDefaults.standard.object(forKey: "attachInNewTab") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "attachInNewTab") }
    }

    // Attaches to the background agent in Ghostty if installed, else Terminal.
    // Ghostty gets a new tab in its front window when it has one; Terminal always gets a new window.
    static func attach(_ sessionId: String) {
        guard let path else { return }
        let id = String(sessionId.prefix(8))
        guard id.allSatisfy(\.isHexDigit) else { return }
        if let tty = attachedTTY(id), Jump.focus(tty: tty) { return }
        let ghosttyId = "com.mitchellh.ghostty"
        if attachInNewTab, !NSRunningApplication.runningApplications(withBundleIdentifier: ghosttyId).isEmpty {
            let script = """
            tell application id "\(ghosttyId)"
                set config to {command:"'\(path)' attach \(id)"}
                if (count of windows) > 0 then
                    new tab in front window with configuration config
                else
                    new window with configuration config
                end if
                activate
            end tell
            """
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        } else if let ghostty = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ghosttyId) {
            _ = run("/usr/bin/open", ["-na", ghostty.path, "--args", "-e", path, "attach", id], in: nil)
        } else {
            let script = "tell application id \"com.apple.Terminal\"\ndo script \"'\(path)' attach \(id)\"\nactivate\nend tell"
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        }
    }

    // The tty of a `claude attach <id>` already running, so a second click reuses its tab.
    private static func attachedTTY(_ id: String) -> String? {
        let (_, out) = run("/bin/ps", ["-ax", "-o", "tty=,args="])
        return out.split(separator: "\n").first { $0.hasSuffix(" attach \(id)") && !$0.hasPrefix("??") }
            .flatMap { $0.split(separator: " ").first.map(String.init) }
    }

    struct Failure: Error {
        let message: String
    }

    @discardableResult
    static func run(_ executable: String, _ args: [String], in folder: String? = nil) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let folder { process.currentDirectoryURL = URL(fileURLWithPath: folder) }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
