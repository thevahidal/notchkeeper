import AppKit
import ServiceManagement
import SwiftUI

// Most settings live in files or UserDefaults, so the view asks to redraw after each change.
final class SettingsModel: ObservableObject {
    let store: SessionStore
    var onPlacementChange: (() -> Void)?
    @Published var error: String?
    @Published var pane: Pane = .office
    @Published var desk: String?

    enum Pane: String, CaseIterable {
        case office = "Office", watches = "Watches", settings = "Settings"

        var icon: String {
            switch self {
            case .office: "building.2"
            case .watches: "eye"
            case .settings: "gearshape"
            }
        }
    }

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

    var pickWorktrees: Bool {
        get { SessionStore.pickWorktrees }
        set { SessionStore.pickWorktrees = newValue; refresh() }
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

    func pluginSetting<T>(_ plugin: Plugin, _ setting: PluginSetting, _ fallback: T) -> Binding<T> {
        Binding(get: { Plugins.values(plugin)[setting.key] as? T ?? fallback },
                set: { Plugins.save(plugin, setting.key, $0); self.refresh() })
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
                Picker(selection: $store.awayMinutes) {
                    Text("Off").tag(0)
                    ForEach([5, 10, 15, 30], id: \.self) { Text("After \($0) min").tag($0) }
                } label: {
                    Text("While you were away")
                    Text("When you're back, sums up who finished and who needs you. Only shows if one did.")
                }
                Toggle(isOn: Binding(get: { model.followsActiveDisplay }, set: { model.followsActiveDisplay = $0 })) {
                    Text("Show on active display")
                    Text("Follows the screen you're working on, instead of staying on the built-in one.")
                }
                Toggle(isOn: Binding(get: { model.attachInNewTab }, set: { model.attachInNewTab = $0 })) {
                    Text("Open background agents in a new tab")
                    Text("In Ghostty's front window when it's open. Off opens a new window each time.")
                }
                Toggle(isOn: Binding(get: { model.pickWorktrees }, set: { model.pickWorktrees = $0 })) {
                    Text("List agent worktrees as folders")
                    Text("In the new agent's folder list. Off lists only your projects, not the worktrees agents made in them.")
                }
                Toggle(isOn: $store.markupHotkey) {
                    Text("Mark up the screen with ⌃⌥D")
                    Text("Freezes the screen so you can draw on something, then asks a new background agent about it.")
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
                    // Only for plugins that are on, so the list stays short.
                    if Plugins.enabled.contains(plugin.id) {
                        ForEach(plugin.settings, id: \.key) { settingRow(plugin, $0).padding(.leading, 16) }
                    }
                }
                Button("Open Plugins Folder") { Plugins.openFolder() }
            } header: {
                Text("Plugins")
            } footer: {
                Text("A plugin runs its script when an agent needs you, finishes, or asks for approval. Each one is off until you turn it on.")
            }

            Section {
                Toggle("Keep an activity log", isOn: Binding(get: { ActivityLog.enabled }, set: { ActivityLog.enabled = $0; model.refresh() }))
                Button("Open Activity Log") { AuditLog.open(ActivityLog.path) }
            } header: {
                Text("Activity")
            } footer: {
                Text("What each agent did today: states, edits and approvals, in ~/.notchkeeper/activity.log. Only you can read it, and it never leaves this Mac.")
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
    }

    @ViewBuilder
    private func settingRow(_ plugin: Plugin, _ setting: PluginSetting) -> some View {
        switch setting.type {
        case "toggle":
            Toggle(setting.title, isOn: model.pluginSetting(plugin, setting, false))
        case "choice":
            Picker(setting.title, selection: model.pluginSetting(plugin, setting, "")) {
                ForEach(setting.options, id: \.self) { Text($0) }
            }
        default:
            TextField(setting.title, text: model.pluginSetting(plugin, setting, ""), prompt: Text(setting.placeholder.isEmpty ? "Not set" : setting.placeholder))
        }
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
        return "Connected · " + agent.spec.note
    }
}

struct MainView: View {
    @ObservedObject var model: SettingsModel
    let watches: Watches

    var body: some View {
        NavigationSplitView {
            List(SettingsModel.Pane.allCases, id: \.self, selection: Binding(get: { model.pane }, set: { if let p = $0 { model.pane = p } })) { pane in
                Label(pane.rawValue, systemImage: pane.icon)
            }
            .navigationSplitViewColumnWidth(160)
        } detail: {
            switch model.pane {
            case .office: OfficeView(model: model, store: model.store)
            case .watches: WatchesView(watches: watches)
            case .settings: SettingsView(model: model, store: model.store)
            }
        }
        .frame(minWidth: 700, minHeight: 600)
    }
}

final class SettingsWindow {
    private static var window: NSWindow?

    static func show(_ model: SettingsModel, _ watches: Watches, pane: SettingsModel.Pane? = nil) {
        if let pane { model.pane = pane }
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: MainView(model: model, watches: watches)))
            window.title = "Notchkeeper"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
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
