import AppKit

// For scripts and package managers: edit the hooks and exit, without starting the app.
if let flag = CommandLine.arguments.dropFirst().first, flag == "--connect" || flag == "--disconnect" {
    do {
        try flag == "--connect" ? HookInstaller.connect() : HookInstaller.disconnect()
        print(flag == "--connect" ? "Notchkeeper connected to Claude Code." : "Notchkeeper disconnected from Claude Code.")
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
