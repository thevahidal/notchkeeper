import AppKit
import ServiceManagement
import SwiftUI

// Most settings live in files or UserDefaults, so the view asks to redraw after each change.
final class SettingsModel: ObservableObject {
    let store: SessionStore
    var onPlacementChange: (() -> Void)?
    @Published var error: String?

    init(store: SessionStore) { self.store = store }

    func refresh() { objectWillChange.send() }

    func toggle(_ agent: Agent) {
        do {
            if HookInstaller.isConnected(agent) {
                try HookInstaller.disconnect(agent)
            } else {
                try HookInstaller.connect(agent)
                if agent == .claude { store.offerConnect = false; store.renamedFromPing = false }
            }
            error = nil
        } catch {
            self.error = "\(agent.title): \(error.localizedDescription)"
        }
        refresh()
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                self.error = "Launch at Login: \(error.localizedDescription)"
            }
            refresh()
        }
    }

    var followsActiveDisplay: Bool {
        get { NotchPanel.followsActiveDisplay }
        set { NotchPanel.followsActiveDisplay = newValue; onPlacementChange?(); refresh() }
    }

    var attachInNewTab: Bool {
        get { ClaudeCLI.attachInNewTab }
        set { ClaudeCLI.attachInNewTab = newValue; refresh() }
    }

    func plugin(_ id: String) -> Binding<Bool> {
        Binding(get: { Plugins.enabled.contains(id) }, set: { on in
            if on { Plugins.enabled.insert(id) } else { Plugins.enabled.remove(id) }
            self.refresh()
        })
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var store: SessionStore
    private let pathLine = "export PATH=\"$HOME/.notchkeeper/bin:$PATH\""

    var body: some View {
        Form {
            if let error = model.error {
                Text(error).foregroundStyle(.red)
            }

            Section {
                ForEach(Agent.allCases, id: \.self) { agent in agentRow(agent) }
            } header: {
                Text("Agents")
            } footer: {
                Text("Connecting adds Notchkeeper's hooks to the agent's settings file and saves a backup next to it. Disconnecting removes only Notchkeeper's entries.")
            }

            Section("Notch") {
                Toggle("Sounds", isOn: $store.sounds)
                Toggle(isOn: $store.quiet) {
                    Text("Quiet mode")
                    Text("The closed notch stays dark until an agent needs you.")
                }
                Toggle(isOn: Binding(get: { model.followsActiveDisplay }, set: { model.followsActiveDisplay = $0 })) {
                    Text("Show on active display")
                    Text("Follows the screen you're working on, instead of staying on the built-in one.")
                }
                Toggle(isOn: Binding(get: { model.attachInNewTab }, set: { model.attachInNewTab = $0 })) {
                    Text("Open background agents in a new tab")
                    Text("In Ghostty's front window when it's open. Off opens a new window each time.")
                }
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
            }

            Section {
                let plugins = Plugins.all
                if plugins.isEmpty {
                    Text("No plugins yet.").foregroundStyle(.secondary)
                }
                ForEach(plugins) { plugin in
                    Toggle(isOn: model.plugin(plugin.id)) {
                        Text(plugin.name)
                        Text(plugin.description)
                    }
                }
                HStack {
                    Button("Add Example Plugins") { Plugins.installExamples(); model.refresh() }
                    Button("Open Plugins Folder") { Plugins.openFolder() }
                }
            } header: {
                Text("Plugins")
            } footer: {
                Text("A plugin runs its script when an agent needs you, finishes, or asks for approval. Each one is off until you turn it on.")
            }

            Section("Approvals") {
                LabeledContent("Shortcuts", value: "⌥Y allow · ⌥N deny")
                Button("Open Approval Log") { AuditLog.open() }
            }

            Section {
                LabeledContent("Command", value: "~/.notchkeeper/bin/notchkeeper")
                HStack {
                    Text(pathLine).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(pathLine, forType: .string)
                    }
                }
            } header: {
                Text("Command line")
            } footer: {
                Text("Add the line to ~/.zshrc, then `notchkeeper run -- npm test` shows any command in the notch.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .frame(minHeight: 720)
    }

    @ViewBuilder
    private func agentRow(_ agent: Agent) -> some View {
        let connected = HookInstaller.isConnected(agent)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.title)
                Text(agentNote(agent, connected)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if agent.isInstalled || connected {
                Button(connected ? "Disconnect" : "Connect") { model.toggle(agent) }
            }
        }
    }

    private func agentNote(_ agent: Agent, _ connected: Bool) -> String {
        if !connected { return agent.isInstalled ? "Not connected" : "Not installed" }
        switch agent {
        case .claude: return "Connected · status and approvals"
        case .codex: return "Connected · approve the hooks in Codex with /hooks"
        case .gemini: return "Connected · status only, approvals stay in Gemini"
        }
    }
}

final class SettingsWindow {
    private static var window: NSWindow?

    static func show(_ model: SettingsModel) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model, store: model.store)))
            window.title = "Notchkeeper Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            // Settings can change outside the app (an agent's file, the plugins folder).
            NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in model.refresh() }
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
