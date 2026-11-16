import Foundation

// Starts agents with no background mode of their own in a detached tmux session; clicking attaches to it.
// tmux gets the command as separate arguments, so it runs it without a shell and a prompt can't run anything.
enum TmuxAgents {
    static let tmux = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"].first { FileManager.default.isExecutableFile(atPath: $0) }

    // The command, and the flag before the first prompt, of agents tested this way.
    private static func command(_ agent: Agent) -> (name: String, flags: [String])? {
        switch agent {
        case .codex: ("codex", [])
        case .gemini: ("gemini", [])
        case .cursor: ("cursor-agent", [])
        case .opencode: ("opencode", ["--prompt"])
        default: nil
        }
    }

    // nvm and similar set PATH in .zshrc, which only an interactive shell reads; Node-based agents need it to find node.
    private static let shell: (path: String, commands: [String: String]) = {
        let names = Agent.allCases.compactMap { command($0)?.name }
        let (_, out) = ClaudeCLI.run("/bin/zsh", ["-lic", "echo \"PATH=$PATH\"; command -v " + names.joined(separator: " ")])
        let lines = out.split(separator: "\n").map(String.init)
        let path = lines.last { $0.hasPrefix("PATH=") }.map { String($0.dropFirst(5)) } ?? "/usr/bin:/bin"
        let found = lines.filter { $0.hasPrefix("/") }
        let commands = Dictionary(names.compactMap { name in found.first { $0.hasSuffix("/" + name) }.map { (name, $0) } }) { a, _ in a }
        return (path, commands)
    }()

    // Claude, plus each agent that's installed and connected, when tmux is there to run it. Looked up off the main thread.
    static func choices(done: @escaping ([Agent]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let others = tmux == nil ? [] : Agent.allCases.filter { agent in
                command(agent).map { shell.commands[$0.name] != nil } == true && HookInstaller.isConnected(agent)
            }
            DispatchQueue.main.async { done([.claude] + others) }
        }
    }

    // A worktree goes where `claude -w` puts its own, so the folder picker and Office treat both alike.
    // Returns the tmux pane id and session name.
    static func launch(_ agent: Agent, prompt: String, in folder: String, worktree: Bool,
                       done: @escaping (Result<(pane: String, session: String), ClaudeCLI.Failure>) -> Void) {
        let fail = { (message: String) in DispatchQueue.main.async { done(.failure(ClaudeCLI.Failure(message: message))) } }
        guard let tmux else { return fail("tmux isn't installed.") }
        guard let (name, flags) = command(agent) else { return fail("\(agent.title) can't start in the background.") }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let path = shell.commands[name] else { return fail("Couldn't find the \(name) command.") }
            let id = ClaudeCLI.name(for: prompt)
            var dir = folder
            if worktree {
                dir = folder + "/.claude/worktrees/" + id
                let (status, out) = ClaudeCLI.run("/usr/bin/git", ["-C", folder, "worktree", "add", "-b", "worktree-" + id, dir])
                if status != 0 { return fail(out.split(separator: "\n").last.map(String.init) ?? "git worktree add failed") }
            }
            let session = "nk-" + id
            let (status, out) = ClaudeCLI.run(tmux, ["new-session", "-d", "-P", "-F", "#{pane_id}", "-s", session, "-c", dir,
                                                     "-e", "PATH=" + shell.path, "--", path] + flags + [prompt])
            let pane = out.trimmingCharacters(in: .whitespacesAndNewlines)
            guard status == 0, pane.range(of: "^%[0-9]+$", options: .regularExpression) != nil else {
                return fail(pane.isEmpty ? "tmux exited with \(status)" : pane)
            }
            DispatchQueue.main.async { done(.success((pane, session))) }
        }
    }

    // Codex runs hooks from its own daemon, so events carry no pane; find the one nk- session started in this folder.
    static func session(inFolder folder: String) -> String? {
        guard let tmux else { return nil }
        let (_, out) = ClaudeCLI.run(tmux, ["list-panes", "-a", "-F", "#{session_name}\t#{pane_current_path}"])
        let names = out.split(separator: "\n").compactMap { line -> String? in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            return parts.count == 2 && parts[0].hasPrefix("nk-") && parts[1] == folder ? parts[0] : nil
        }
        return names.count == 1 ? names[0] : nil
    }

    // Focuses the terminal already attached to it, or attaches in a new one.
    static func attach(_ session: String) {
        guard let tmux, session.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return }
        let (_, out) = ClaudeCLI.run(tmux, ["list-clients", "-t", session, "-F", "#{client_tty}"])
        if let tty = out.split(separator: "\n").first?.replacingOccurrences(of: "/dev/", with: ""), Jump.focus(tty: tty) { return }
        ClaudeCLI.openTerminal([tmux, "attach", "-t", session])
    }
}
