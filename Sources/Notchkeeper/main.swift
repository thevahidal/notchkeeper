import AppKit

// For scripts and package managers: edit the hooks and exit, without starting the app.
if let flag = CommandLine.arguments.dropFirst().first, flag == "--connect" || flag == "--disconnect" {
    // An optional second argument names the agent: claude (default), codex or gemini.
    let name = CommandLine.arguments.dropFirst(2).first ?? "claude"
    do {
        guard let agent = Agent(rawValue: name) else { throw HookInstaller.Failure(errorDescription: "unknown agent \(name)") }
        try flag == "--connect" ? HookInstaller.connect(agent) : HookInstaller.disconnect(agent)
        print(flag == "--connect" ? "Notchkeeper connected to \(agent.title)." : "Notchkeeper disconnected from \(agent.title).")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Notchkeeper: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
