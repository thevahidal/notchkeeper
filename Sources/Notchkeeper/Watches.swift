import AppKit
import SwiftUI

// Commands and timers started from the window. Each shows in the notch like `notchkeeper run`.
// Kept in memory only: a saved list of commands is something else could plant for the app to run.
final class Watches: ObservableObject {
    struct Watch: Identifiable {
        let id = String(UUID().uuidString.prefix(8))
        let title: String
        let isCommand: Bool
        let started = Date()
        var ends: Date?
        var result: String?
    }

    @Published private(set) var list: [Watch] = []
    @Published var command = ""
    @Published var folder = FileManager.default.homeDirectoryForCurrentUser
    @Published var timerName = ""
    @Published var minutes = 25

    private let store: SessionStore
    private var processes: [String: Process] = [:]
    private var timers: [String: Timer] = [:]

    init(store: SessionStore) { self.store = store }

    func run() {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        let watch = Watch(title: command, isCommand: true)
        let process = Process()
        // Login shell, so PATH from ~/.zprofile (Homebrew and the like) applies.
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = folder
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] p in
            DispatchQueue.main.async { self?.ended(watch.id, code: p.terminationStatus) }
        }
        list.insert(watch, at: 0)
        do { try process.run() } catch {
            return finish(watch.id, "needs-you", "Couldn't start: \(error.localizedDescription)")
        }
        processes[watch.id] = process
        send(watch, "working", "Running in \(folder.lastPathComponent)")
        self.command = ""
    }

    func startTimer() {
        let name = timerName.trimmingCharacters(in: .whitespacesAndNewlines)
        var watch = Watch(title: name.isEmpty ? "\(minutes) min timer" : name, isCommand: false)
        let ends = Date().addingTimeInterval(TimeInterval(minutes * 60))
        watch.ends = ends
        list.insert(watch, at: 0)
        send(watch, "working", "Ends at \(ends.formatted(date: .omitted, time: .shortened))")
        timers[watch.id] = Timer.scheduledTimer(withTimeInterval: ends.timeIntervalSinceNow, repeats: false) { [weak self] _ in
            self?.finish(watch.id, "done", "Time's up")
        }
        timerName = ""
    }

    func stop(_ id: String) {
        guard let i = list.firstIndex(where: { $0.id == id }), list[i].result == nil else { return }
        list[i].result = "Stopped"
        timers.removeValue(forKey: id)?.invalidate()
        processes.removeValue(forKey: id)?.terminate()
        send(list[i], "remove", "")
    }

    func stopAll() { list.filter { $0.result == nil }.forEach { stop($0.id) } }

    func clearFinished() { list.removeAll { $0.result != nil } }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = folder
        if panel.runModal() == .OK, let url = panel.url { folder = url }
    }

    private func ended(_ id: String, code: Int32) {
        guard processes.removeValue(forKey: id) != nil, let watch = list.first(where: { $0.id == id }) else { return }
        let took = Items.duration(Date().timeIntervalSince(watch.started))
        if code == 0 { finish(id, "done", "Finished in \(took)") } else { finish(id, "needs-you", "Failed with exit \(code) after \(took)") }
    }

    private func finish(_ id: String, _ state: String, _ detail: String) {
        guard let i = list.firstIndex(where: { $0.id == id }), list[i].result == nil else { return }
        timers.removeValue(forKey: id)
        list[i].result = detail
        send(list[i], state, detail)
    }

    private func send(_ watch: Watch, _ state: String, _ detail: String) {
        var event = Items.event(id: watch.id, title: watch.title, state: state, detail: detail, url: nil, source: "watch")
        event["cwd"] = folder.path
        store.apply(event)
    }
}

struct WatchesView: View {
    @ObservedObject var watches: Watches

    var body: some View {
        Form {
            Section {
                TextField("Command", text: $watches.command, prompt: Text("npm test"))
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { watches.run() }
                HStack {
                    Text((watches.folder.path as NSString).abbreviatingWithTildeInPath).foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose Folder…") { watches.chooseFolder() }
                    Button("Run") { watches.run() }.disabled(watches.command.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Run a command")
            } footer: {
                Text("Runs in a login shell. The notch tells you when it finishes or fails.")
            }

            Section("Set a timer") {
                TextField("Name", text: $watches.timerName, prompt: Text("Stand-up"))
                Stepper("\(watches.minutes) min", value: $watches.minutes, in: 1...480)
                Button("Start Timer") { watches.startTimer() }
            }

            Section {
                if watches.list.isEmpty {
                    Text("Commands and timers you start show up here.").foregroundStyle(.secondary)
                }
                ForEach(watches.list) { watch in row(watch) }
            } header: {
                HStack {
                    Text("Watches")
                    Spacer()
                    if watches.list.contains(where: { $0.result != nil }) {
                        Button("Clear Finished") { watches.clearFinished() }.buttonStyle(.link)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ watch: Watches.Watch) -> some View {
        HStack {
            Image(systemName: watch.isCommand ? "terminal" : "timer").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(watch.title).font(watch.isCommand ? .system(.body, design: .monospaced) : .body).lineLimit(1)
                Text(status(watch)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if watch.result == nil { Button("Stop") { watches.stop(watch.id) } }
        }
    }

    private func status(_ watch: Watches.Watch) -> String {
        if let result = watch.result { return result }
        if let ends = watch.ends { return "Ends at \(ends.formatted(date: .omitted, time: .shortened))" }
        return "Running since \(watch.started.formatted(date: .omitted, time: .shortened))"
    }
}
