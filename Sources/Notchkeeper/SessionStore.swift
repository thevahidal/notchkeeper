import SwiftUI

enum SessionState: String, Codable {
    case working, needsYou, yourTurn
}

enum Mood {
    case idle, working, needsYou, yourTurn
}

struct Session: Identifiable, Codable {
    let id: String
    var repo: String
    var title = ""
    // Claude's own title (from its sidebar) wins over a plugin's, which wins over the first prompt.
    var ownTitle: String?
    var pluginTitle: String?
    // A plugin's one- or two-word name for the notch's side, where a title won't fit.
    var label: String?
    var cwd = ""
    // Claude's transcript, checked to be under ~/.claude*/projects (CLAUDE_CONFIG_DIR profiles too).
    var transcript: String?
    var branch: String?
    // Started with `claude --bg`: no terminal tab of its own, you attach to it.
    var background = false
    // Started from the notch in a detached tmux session (agents with no background mode of their own).
    var tmuxSession: String?
    // Not an agent: something posted with `notchkeeper notify` or `run`. Clicking opens its link, if any.
    var isItem = false
    var url: String?
    var tty: String?
    var term: String?
    // Bundle id of the app the terminal runs in, from the hook's environment; a fallback for terminals Notchkeeper can't script.
    var app: String?
    // nil for Claude Code; "codex" or "gemini" otherwise.
    var agent: String?
    var pane: Pane?
    // The desktop app's question box from the latest turn.
    var question: String?
    var seen = false
    var mode: String?
    var model: String?
    var effort: String?
    var subagents: [Subagent] = []
    // File name → last time this agent (or its subagents) edited it.
    var edited: [String: Date] = [:]
    // Work at risk in its folder, like "3 uncommitted · 2 unpushed".
    var unsaved: String?
    // The agent is gone; kept only because it left unsaved work behind.
    var ended = false
    var state: SessionState
    // "Remind me later": hidden from alerts until then.
    var snoozedUntil: Date?
    // When it entered the current state.
    var since = Date()
    var detail: String
    var lastSeen: Date

    // The project it works in. Items show their source in the notch, but sit at the folder they ran in.
    var desk: String { isItem && !cwd.isEmpty ? (cwd as NSString).lastPathComponent : repo }
}

// A pane inside a multiplexer or a scriptable terminal, for exact jumps and replies.
enum Pane: Equatable, Codable {
    case tmux(socket: String, pane: String)
    case wezterm(pane: String)
    case kitty(socket: String, window: String)

    // Each id goes into a command line, so only the expected shapes pass.
    init?(_ event: [String: Any]) {
        func field(_ key: String, _ pattern: String) -> String? {
            (event[key] as? String).flatMap { $0.range(of: pattern, options: .regularExpression) != nil ? $0 : nil }
        }
        if let pane = field("tmux_pane", "^%[0-9]+$"), let socket = field("tmux_socket", "^/[A-Za-z0-9/._-]+$"), !socket.contains("..") {
            self = .tmux(socket: socket, pane: pane)
        } else if let pane = field("wezterm_pane", "^[0-9]+$") {
            self = .wezterm(pane: pane)
        } else if let window = field("kitty_window", "^[0-9]+$"), let socket = field("kitty_socket", "^unix:/[A-Za-z0-9/._-]+$"),
                  !socket.contains("..") {
            self = .kitty(socket: socket, window: window)
        } else {
            return nil
        }
    }
}

struct Subagent: Identifiable, Codable {
    let id: String
    let type: String
    let description: String
    var detail = ""
}

struct Approval: Identifiable {
    let id = UUID()
    let shown = Date()
    let sessionId: String
    // Set when a subagent asked, so the parent's own events don't settle it.
    let agentId: String?
    let repo: String
    let tool: String
    let target: String
    // Claude's own "don't ask again" rules for this request, narrowed to this session.
    let sessionRules: [[String: Any]]
    let risk: Risk
    // For edits: the lines removed ("-") and added ("+"), trimmed to a few.
    let diff: [(sign: Character, text: String)]
    let expires: Date
    let reply: EventServer.Reply
}

// What changed while you were away: one line per agent that did something.
struct CatchUp {
    struct Item: Identifiable {
        let id: String
        let state: SessionState
        let title: String
        let detail: String
        let files: [String]
    }
    let since: Date
    let items: [Item]
}

struct NewAgent {
    var folder: String
    var agent = Agent(rawValue: UserDefaults.standard.string(forKey: "newAgentKind") ?? "") ?? .claude
    var prompt = ""
    var worktree: Bool
    var images: [URL] = []
    var error: String?
    var busy = false
}

struct PlanReview {
    let sessionId: String
    let repo: String
    let plan: String
}

final class SessionStore: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var approvals: [Approval] = []
    @Published var plan: PlanReview?
    @Published var catchUp: CatchUp?
    @Published var newAgent: NewAgent?
    // Agents the new agent card can start.
    @Published var agentChoices: [Agent] = [.claude]
    // Follow-ups typed while an agent works, sent in order when its turn ends.
    @Published var queued: [String: [String]] = [:]
    // The approval whose "tell Claude" field is open, and what you've typed.
    @Published var feedbackFor: UUID?
    @Published var feedback = ""
    // Short ids printed by `claude --bg` for agents started here.
    private var launched: Set<String> = []
    // tmux pane id → session name, for agents started here in tmux.
    private var launchedPanes: [String: String] = [:]
    private var awaySince: Date?
    @Published var sounds = UserDefaults.standard.object(forKey: "sounds") as? Bool ?? true {
        didSet { UserDefaults.standard.set(sounds, forKey: "sounds") }
    }
    // Collapsed notch stays dark until an agent needs you.
    @Published var quiet = UserDefaults.standard.bool(forKey: "quiet") {
        didSet { UserDefaults.standard.set(quiet, forKey: "quiet") }
    }
    @Published var markupHotkey = UserDefaults.standard.object(forKey: "markupHotkey") as? Bool ?? true {
        didSet { UserDefaults.standard.set(markupHotkey, forKey: "markupHotkey") }
    }
    // Minutes idle before the "While you were away" card; 0 turns it off.
    @Published var awayMinutes = UserDefaults.standard.object(forKey: "awayMinutes") as? Int ?? 10 {
        didSet { UserDefaults.standard.set(awayMinutes, forKey: "awayMinutes") }
    }
    @Published var replyTo: Session? {
        didSet { if replyTo?.id != oldValue?.id { loadChat(); pastedImages = [] } }
    }
    // Images pasted into the reply field; their paths are sent at the end of the message.
    @Published var pastedImages: [URL] = []
    static let pasteDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Notchkeeper/Pasted")
    // The recent conversation of the session you're replying to.
    @Published var chat: [ChatLine] = []
    @Published var draft = ""
    // First launch: ask before touching ~/.claude/settings.json.
    @Published var offerConnect = false
    @Published var connectError: String?
    // Hooks from the app's old name are in settings: the connect card offers to update them.
    var renamedFromPing = false
    static let approvalTimeout: TimeInterval = 29
    // Descriptions from Agent tool calls, waiting for their SubagentStart (which has the id).
    private var pendingAgents: [String: [String]] = [:]

    // Most urgent first, seen ones last, then most recent.
    var sorted: [Session] {
        func rank(_ s: Session) -> Int { s.snoozedUntil != nil ? 4 : s.seen ? 3 : s.state == .needsYou ? 0 : s.state == .yourTurn ? 1 : 2 }
        return sessions.sorted { (rank($0), $1.lastSeen) < (rank($1), $0.lastSeen) }
    }

    var mood: Mood {
        let awake = sessions.filter { $0.snoozedUntil == nil }
        if awake.contains(where: { $0.state == .needsYou }) { return .needsYou }
        if awake.contains(where: { $0.state == .working }) { return .working }
        return awake.contains { $0.state == .yourTurn && !$0.seen } ? .yourTurn : .idle
    }

    // The one session the collapsed notch names: the most urgent one still waiting on you.
    var headline: Session? {
        sorted.first { !$0.seen && $0.state != .working && $0.snoozedUntil == nil }
    }

    // Typing into the notch: the panel needs the keyboard.
    var typing: Bool { replyTo != nil || newAgent != nil || approvals.contains { $0.id == feedbackFor } }

    // Folders agents ran in lately, newest first, for the new agent picker.
    var recentFolders: [String] {
        // Worktrees agents made (claude -w puts them in .claude/worktrees) are hidden by default; you pick the repo.
        Array(knownFolders.filter { Self.pickWorktrees || !$0.contains("/.claude/worktrees/") }.prefix(8))
    }

    var knownFolders: [String] {
        let live = sessions.sorted { $0.lastSeen > $1.lastSeen }.map(\.cwd)
        let saved = UserDefaults.standard.stringArray(forKey: "recentFolders") ?? []
        var seen = Set<String>()
        return (live + saved).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static var pickWorktrees: Bool {
        get { UserDefaults.standard.bool(forKey: "pickWorktrees") }
        set { UserDefaults.standard.set(newValue, forKey: "pickWorktrees") }
    }

    func openNewAgent(in folder: String? = nil) {
        let folder = folder ?? recentFolders.first ?? NSHomeDirectory()
        newAgent = NewAgent(folder: folder, worktree: Self.gitBranch(folder) != nil, images: newAgent?.images ?? [])
        TmuxAgents.choices { [weak self] choices in
            self?.agentChoices = choices
            if let agent = self?.newAgent?.agent, !choices.contains(agent) { self?.newAgent?.agent = .claude }
        }
    }

    func launchAgent() {
        guard var draft = newAgent, !draft.busy else { return }
        let typed = draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        let prompt = ([typed] + draft.images.map(\.path)).joined(separator: " ")
        draft.busy = true
        draft.error = nil
        newAgent = draft
        let worktree = draft.worktree && Self.gitBranch(draft.folder) != nil
        UserDefaults.standard.set(draft.agent.rawValue, forKey: "newAgentKind")
        let finished = { [weak self] (result: Result<Void, ClaudeCLI.Failure>) in
            guard let self else { return }
            switch result {
            case .success:
                let saved = UserDefaults.standard.stringArray(forKey: "recentFolders") ?? []
                UserDefaults.standard.set(Array(([draft.folder] + saved.filter { $0 != draft.folder }).prefix(8)), forKey: "recentFolders")
                self.newAgent = nil
            case .failure(let failure):
                self.newAgent?.busy = false
                self.newAgent?.error = failure.message
            }
        }
        if draft.agent == .claude {
            ClaudeCLI.launch(prompt: prompt, in: draft.folder, worktree: worktree) { [weak self] result in
                finished(result.map { self?.launched.insert($0); return () })
            }
        } else {
            TmuxAgents.launch(draft.agent, prompt: prompt, in: draft.folder, worktree: worktree) { [weak self] result in
                finished(result.map { launched in
                    guard let self else { return () }
                    self.launchedPanes[launched.pane] = launched.session
                    // A fast CLI can send its first hook before tmux returns the pane id.
                    // Reconcile that event here as well as when later events arrive.
                    if let i = self.sessions.firstIndex(where: { session in
                        if case let .tmux(_, pane)? = session.pane { return pane == launched.pane }
                        return false
                    }) { self.sessions[i].tmuxSession = launched.session }
                    return ()
                })
            }
        }
    }

    func jump(to session: Session) {
        if session.isItem {
            if let url = session.url.flatMap(URL.init) { NSWorkspace.shared.open(url) }
        } else if session.ended {
            Jump.open(folder: session.cwd, for: session)
        } else if let name = session.tmuxSession {
            TmuxAgents.attach(name)
        } else if session.background {
            ClaudeCLI.attach(session.id)
        } else {
            Jump.to(session)
        }
        markSeen(session.id)
    }

    // Only "your turn" can be seen; a question or approval still needs an answer.
    private func markSeen(_ id: String) {
        guard let i = sessions.firstIndex(where: { $0.id == id }), sessions[i].state == .yourTurn else { return }
        sessions[i].seen = true
    }

    func answer(_ approval: Approval, _ decision: String) {
        // Ignore clicks and hotkeys that land as the card pops up; you haven't read it yet.
        // Risky calls get a longer pause, so a reflexive ⌥Y can't wave them through.
        let pause = approval.risk.level == .high ? 1.5 : 0.7
        guard decision == "terminal" || Date().timeIntervalSince(approval.shown) > pause else { return }
        AuditLog.record(approval, decision)
        if decision == "deny-message" {
            // A JSON string, so the hook can drop it into its output as is.
            let message = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty, let data = try? JSONSerialization.data(withJSONObject: message, options: .fragmentsAllowed) else { return }
            approval.reply("deny-message " + String(decoding: data, as: UTF8.self))
            feedbackFor = nil
            feedback = ""
        } else if decision == "session" {
            // One line of JSON built from Claude's own suggestions; the hook passes it back as is.
            guard let data = try? JSONSerialization.data(withJSONObject: approval.sessionRules) else { return }
            approval.reply("allow-session " + String(decoding: data, as: UTF8.self))
        } else {
            approval.reply(decision)
        }
        approvals.removeAll { $0.id == approval.id }
    }

    func connect() {
        do {
            try HookInstaller.connect()
            offerConnect = false
            renamedFromPing = false
        } catch {
            connectError = error.localizedDescription
        }
    }

    func declineConnect() {
        offerConnect = false
        UserDefaults.standard.set(true, forKey: "declinedConnect")
    }

    // ⌘V with an image on the clipboard, in a reply or new agent: save it as a PNG. Returns false to let the field paste text.
    func pasteImage() -> Bool {
        let board = NSPasteboard.general
        guard replyTo != nil || newAgent != nil, board.string(forType: .string) == nil,
              let tiff = NSImage(pasteboard: board)?.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return false }
        let url = Self.pasteDir.appendingPathComponent(UUID().uuidString + ".png")
        try? FileManager.default.createDirectory(at: Self.pasteDir, withIntermediateDirectories: true)
        guard (try? png.write(to: url)) != nil else { return false }
        if newAgent != nil { newAgent?.images.append(url) } else { pastedImages.append(url) }
        return true
    }

    // Draw on the screen, then ask a new background agent about it.
    func markUpScreen() {
        Markup.start { [weak self] url in
            self?.newAgent = nil
            self?.openNewAgent()
            self?.newAgent?.images = [url]
        }
    }

    func removePastedImage(_ url: URL) {
        pastedImages.removeAll { $0 == url }
        try? FileManager.default.removeItem(at: url)
    }

    func sendReply() {
        let text = ([draft.trimmingCharacters(in: .whitespacesAndNewlines)] + pastedImages.map(\.path))
            .filter { !$0.isEmpty }.joined(separator: " ")
        if let session = replyTo, !text.isEmpty {
            if sessions.first(where: { $0.id == session.id })?.state == .working {
                queued[session.id, default: []].append(text)
            } else if !Jump.reply(session, text) {
                // Not typed (e.g. Claude has exited): take you to the tab instead.
                Jump.to(session)
            }
        }
        replyTo = nil
        draft = ""
    }

    // The turn ended without a question: send the next queued follow-up.
    private func sendQueued(_ i: Int) {
        guard let next = queued[sessions[i].id]?.first, Jump.reply(sessions[i], next) else { return }
        queued[sessions[i].id]?.removeFirst()
        if queued[sessions[i].id]?.isEmpty == true { queued[sessions[i].id] = nil }
        sessions[i].state = .working
        sessions[i].since = Date()
        sessions[i].detail = "Queued: " + next
    }

    func apply(_ raw: [String: Any], reply: EventServer.Reply? = nil) {
        let agent = (raw["agent"] as? String).flatMap(Agent.init).flatMap { $0 == .claude ? nil : $0 }
        let event = agent?.normalize(raw) ?? raw
        guard let id = event["session_id"] as? String, let name = event["hook_event_name"] as? String else { return }
        if name == "Item" { return applyItem(id, event) }
        let repo = ((event["cwd"] as? String ?? "") as NSString).lastPathComponent
        let agentId = event["agent_id"] as? String

        // Any later event from the same agent means the request was settled elsewhere, e.g. in the terminal.
        approvals.removeAll { $0.sessionId == id && $0.agentId == agentId }
        if plan?.sessionId == id && name != "Notification" { plan = nil }
        // Claude ignores a hook's answer to ExitPlanMode, so don't hold it: show the plan and let Claude ask as usual.
        if let reply, Self.tool(event) == "ExitPlanMode" {
            reply("")
            let text = (event["tool_input"] as? [String: Any])?["plan"] as? String ?? ""
            if !text.isEmpty { plan = PlanReview(sessionId: id, repo: repo, plan: text) }
        } else if let reply {
            let input = event["tool_input"] as? [String: Any] ?? [:]
            let risk = Risk(tool: Self.tool(event), input: input, cwd: event["cwd"] as? String ?? "")
            let approval = Approval(
                sessionId: id, agentId: agentId, repo: repo, tool: Self.tool(event), target: Self.target(event) ?? "",
                // Never offer to stop asking about something that looks dangerous.
                sessionRules: risk.level == .high ? [] : Self.sessionRules(event),
                risk: risk, diff: Self.diff(input),
                expires: Date().addingTimeInterval(Self.approvalTimeout), reply: reply
            )
            approvals.append(approval)
            if let session = sessions.first(where: { $0.id == id }) {
                emit("approval", session, extra: ["tool": approval.tool, "target": approval.target,
                                                  "risk": ["low", "medium", "high"][risk.level.rawValue]])
            }
            // The hook gives up after 30s, so drop the card just before that.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.approvalTimeout) { [weak self] in
                guard let self, self.approvals.contains(where: { $0.id == approval.id }) else { return }
                AuditLog.record(approval, "timeout")
                self.approvals.removeAll { $0.id == approval.id }
            }
        }

        if name == "SessionEnd" {
            if let session = sessions.first(where: { $0.id == id }) { ActivityLog.record("end", session) }
            return end([id])
        }

        // Sent after ~60s of no reply; it changes nothing about the session.
        if event["notification_type"] as? String == "idle_prompt" { return }

        if name == "PreToolUse", Self.tool(event) == "Agent",
           let description = (event["tool_input"] as? [String: Any])?["description"] as? String {
            pendingAgents[id, default: []].append(description)
        }
        // A subagent's own activity goes on its line under the parent; only its prompts reach the parent.
        if let agentId, name != "PermissionRequest", name != "Notification" {
            return applySubagent(id, agentId, name, event)
        }

        let state: SessionState
        switch name {
        // Claude's multiple-choice question blocks until you pick an answer.
        case "PreToolUse" where Self.tool(event) == "AskUserQuestion": state = .needsYou
        case "UserPromptSubmit", "PreToolUse", "PostToolUse": state = .working
        case "Notification", "PermissionRequest": state = .needsYou
        case "Stop": state = .yourTurn
        default: return
        }

        let detail = describe(name, event)
        let isNew = !sessions.contains { $0.id == id }
        if isNew || name == "Stop" { loadTitle(id, transcript: event["transcript_path"] as? String, turnEnded: name == "Stop") }
        if isNew || name == "Stop", let cwd = event["cwd"] as? String { loadBranch(id, cwd: cwd) }
        if name == "Stop", let cwd = event["cwd"] as? String { loadUnsaved(id, cwd: cwd) }
        if !sessions.contains(where: { $0.id == id }) {
            var session = Session(id: id, repo: repo, state: state, detail: "", lastSeen: Date())
            session.background = launched.contains(String(id.prefix(8)))
            sessions.append(session)
            // A terminal Ping can't name may be a background agent started elsewhere; ask Claude.
            if !session.background, event["tty"] as? String != "??", (event["term"] as? String ?? "").isEmpty {
                ClaudeCLI.backgroundSessions { [weak self] ids in
                    guard ids.contains(id), let i = self?.sessions.firstIndex(where: { $0.id == id }) else { return }
                    self?.sessions[i].background = true
                }
            }
        }
        let i = sessions.firstIndex { $0.id == id }!
        sessions[i].ended = false
        noteEdit(i, name, event)
        let entered = sessions[i].state != state || isNew
        if sessions[i].state != state {
            sessions[i].since = Date()
            sessions[i].snoozedUntil = nil
        }
        sessions[i].state = state
        sessions[i].detail = detail ?? sessions[i].detail
        if state == .working { sessions[i].question = nil }
        sessions[i].lastSeen = Date()
        if let cwd = event["cwd"] as? String { sessions[i].cwd = cwd }
        if let path = Self.claudeTranscript(event["transcript_path"] as? String) { sessions[i].transcript = path }
        // Only notchkeeper-hook.sh sends these; "??" means no terminal, i.e. the desktop app.
        if let tty = event["tty"] as? String {
            // It ends up inside an AppleScript, so accept only the "ttys012" shape.
            sessions[i].tty = tty.range(of: "^ttys[0-9]+$", options: .regularExpression) != nil ? tty : nil
            sessions[i].term = event["term"] as? String
            sessions[i].app = (event["app"] as? String).flatMap { $0.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil ? $0 : nil }
            sessions[i].pane = Pane(event)
            if case let .tmux(_, pane)? = sessions[i].pane, let name = launchedPanes[pane] { sessions[i].tmuxSession = name }
        }
        if let mode = event["permission_mode"] as? String { sessions[i].mode = mode }
        // Claude's titles and model come from its transcript; the others tell us in the event.
        if let agent {
            sessions[i].agent = agent.rawValue
            if sessions[i].title.isEmpty, let prompt = event["prompt"] as? String { sessions[i].title = String(firstLine(prompt)?.prefix(80) ?? "") }
            if let model = event["model"] as? String { sessions[i].model = model }
        }
        if let effort = (event["effort"] as? [String: Any])?["level"] as? String { sessions[i].effort = effort }
        if name == "UserPromptSubmit", let prompt = event["prompt"] as? String {
            emit("prompt", sessions[i], extra: ["prompt": String(prompt.prefix(4000))])
        }
        if name == "Stop", let message = event["last_assistant_message"] as? String {
            emit("reply", sessions[i], extra: ["message": String(message.prefix(4000))])
        }
        if entered { ActivityLog.record(state.rawValue, sessions[i]) }
        // A new event is unseen, unless it finished in the tab you're already looking at.
        sessions[i].seen = false
        // An AppleScript round trip, so only when it matters.
        let looking = (name == "Stop" || (entered && state != .working)) && Jump.isFrontmost(sessions[i])
        if name == "Stop" && looking { markSeen(id) }
        if entered && state != .working && !looking { alert(i) }
    }

    private var lastChime = Date.distantPast

    // An agent just started waiting on you or finished: sound, and tell any plugins that asked.
    private func alert(_ i: Int) {
        chime(sessions[i].state)
        emit(sessions[i].state == .needsYou ? "needs-you" : "done", sessions[i])
    }

    private func emit(_ event: String, _ session: Session, extra: [String: Any] = [:]) {
        let id = session.id
        Plugins.emit(event, session, extra: extra) { [weak self] reply in self?.applyPluginReply(id, reply) }
    }

    // A plugin's reply only touches the session that triggered it.
    private func applyPluginReply(_ id: String, _ reply: [String: Any]) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        if let title = firstLine(reply["title"] as? String) {
            sessions[i].pluginTitle = String(title.prefix(80))
            if sessions[i].ownTitle == nil { sessions[i].title = String(title.prefix(80)) }
        }
        if let label = firstLine(reply["label"] as? String) { sessions[i].label = String(label.prefix(20)) }
        if let detail = firstLine(reply["detail"] as? String) { sessions[i].detail = String(detail.prefix(200)) }
    }

    func chime(_ state: SessionState) {
        guard sounds, Date().timeIntervalSince(lastChime) > 2 else { return }
        lastChime = Date()
        NSSound(named: state == .needsYou ? "Ping" : "Pop")?.play()
    }

    private func noteEdit(_ i: Int, _ name: String, _ event: [String: Any]) {
        guard name == "PostToolUse", ["Edit", "Write", "MultiEdit", "NotebookEdit"].contains(Self.tool(event)),
              let file = Self.target(event) else { return }
        let hourAgo = Date().addingTimeInterval(-3600)
        sessions[i].edited = sessions[i].edited.filter { $0.value > hourAgo }
        sessions[i].edited[file] = Date()
        ActivityLog.record("edit", desk: sessions[i].desk, session: sessions[i].id, agent: sessions[i].agent ?? "claude", detail: file,
                           file: (event["tool_input"] as? [String: Any])?["file_path"] as? String)
    }

    static var idleSeconds: TimeInterval {
        [CGEventType.keyDown, .mouseMoved, .leftMouseDown]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    // Away for a while, then back: brief you once, but only if someone finished or needs you.
    func checkPresence() {
        guard awayMinutes > 0 else { awaySince = nil; return }
        let idle = Self.idleSeconds
        if idle > TimeInterval(awayMinutes * 60) {
            if awaySince == nil { awaySince = Date().addingTimeInterval(-idle) }
            return
        }
        guard let since = awaySince, idle < 5 else { return }
        awaySince = nil
        let items = sorted.compactMap { s -> CatchUp.Item? in
            let files = s.edited.filter { $0.value > since }.sorted { $0.value > $1.value }.map(\.key)
            guard s.snoozedUntil == nil, s.since > since || !files.isEmpty else { return nil }
            return CatchUp.Item(id: s.id, state: s.state, title: s.title.isEmpty ? s.repo : s.title,
                                detail: s.question ?? s.detail, files: files)
        }
        guard items.contains(where: { $0.state != .working }) else { return }
        catchUp = CatchUp(since: since, items: items)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            if self?.catchUp?.since == since { self?.catchUp = nil }
        }
    }

    // While something has needed you for a few minutes and you've stepped away, remind you once in a while.
    // Something's been waiting on you: a ping every 10 minutes, every 3 if you've stepped away. Snoozes wake here too.
    func remind() {
        for i in sessions.indices {
            guard let until = sessions[i].snoozedUntil, until <= Date() else { continue }
            sessions[i].snoozedUntil = nil
            sessions[i].seen = false
            chime(sessions[i].state)
        }
        let waiting = sessions.filter { $0.state == .needsYou && $0.snoozedUntil == nil }.map { Date().timeIntervalSince($0.since) }.max() ?? 0
        let gap: TimeInterval = Self.idleSeconds > 60 ? 180 : 600
        if waiting > gap && Date().timeIntervalSince(lastChime) > gap { chime(.needsYou) }
    }

    func snooze(_ session: Session, until date: Date) {
        guard let i = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[i].snoozedUntil = date
    }

    private func applySubagent(_ id: String, _ agentId: String, _ name: String, _ event: [String: Any]) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        if name == "SubagentStop" { return sessions[i].subagents.removeAll { $0.id == agentId } }
        if !sessions[i].subagents.contains(where: { $0.id == agentId }) {
            let description = pendingAgents[id]?.isEmpty == false ? pendingAgents[id]!.removeFirst() : ""
            sessions[i].subagents.append(Subagent(id: agentId, type: event["agent_type"] as? String ?? "Agent", description: description))
        }
        noteEdit(i, name, event)
        if name == "PreToolUse", let j = sessions[i].subagents.firstIndex(where: { $0.id == agentId }) {
            sessions[i].subagents[j].detail = describe(name, event) ?? ""
        }
    }

    // Off the notch until its next event brings it back.
    func dismiss(_ id: String) {
        queued[id] = nil
        sessions.removeAll { $0.id == id }
    }

    // Leaves agents with unsaved work; those close one at a time, on purpose.
    func clearFinished() {
        sessions.filter { $0.state == .yourTurn && !$0.ended }.forEach { dismiss($0.id) }
    }

    // Fallback for sessions that ended without a SessionEnd. Anything still waiting on you stays a day, so it isn't forgotten.
    // Ended agents with unsaved work stay until it's saved or you close them.
    func pruneStale() {
        sessions.removeAll { s in
            if s.ended { return false }
            let waiting = s.state == .needsYou || (s.state == .yourTurn && !s.seen) || s.snoozedUntil != nil
            let ttl: TimeInterval = waiting ? 24 * 3600 : s.seen ? 10 * 60 : 30 * 60
            return s.lastSeen < Date().addingTimeInterval(-ttl)
        }
        dropClosedTerminals()
        recheckUnsaved()
    }

    // The agent is gone. Unsaved work in its folder keeps it on the notch, once per folder; otherwise it's dropped.
    private func end(_ ids: [String]) {
        ids.forEach { queued[$0] = nil }
        let folders = sessions.filter { ids.contains($0.id) }.map { ($0.id, $0.cwd) }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = folders.map { ($0.0, $0.1, Self.unsavedWork($0.1)) }
            DispatchQueue.main.async {
                guard let self else { return }
                for (id, cwd, work) in found {
                    // A live agent in the same folder already shows it.
                    let covered = self.sessions.contains { $0.id != id && $0.cwd == cwd && !ids.contains($0.id) }
                    guard let work, !covered, let i = self.sessions.firstIndex(where: { $0.id == id }) else {
                        self.sessions.removeAll { $0.id == id }
                        continue
                    }
                    self.sessions[i].ended = true
                    self.sessions[i].unsaved = work
                    self.sessions[i].state = .yourTurn
                    self.sessions[i].detail = "Ended with unsaved work"
                    self.sessions[i].question = nil
                    self.sessions[i].subagents = []
                    self.sessions[i].seen = false
                    self.sessions[i].since = Date()
                    self.sessions[i].lastSeen = Date()
                    self.chime(.yourTurn)
                }
            }
        }
    }

    // You may commit or push from elsewhere; chips clear and ended agents go once their folder is clean.
    private func recheckUnsaved() {
        let flagged = sessions.filter { $0.ended || $0.unsaved != nil }.map { ($0.id, $0.cwd) }
        guard !flagged.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = flagged.map { ($0.0, Self.unsavedWork($0.1)) }
            DispatchQueue.main.async {
                guard let self else { return }
                for (id, work) in found {
                    guard let i = self.sessions.firstIndex(where: { $0.id == id }) else { continue }
                    if work == nil && self.sessions[i].ended { self.sessions.remove(at: i) } else { self.sessions[i].unsaved = work }
                }
            }
        }
    }

    // Uncommitted files, and commits on no remote. Read-only, and skips git's optional locks so it never blocks the agent's own git.
    static func unsavedWork(_ cwd: String) -> String? {
        guard !cwd.isEmpty, gitBranch(cwd) != nil else { return nil }
        func git(_ args: [String]) -> (Int32, String) { ClaudeCLI.run("/usr/bin/git", ["--no-optional-locks", "-C", cwd] + args) }
        let (status, changes) = git(["status", "--porcelain"])
        guard status == 0 else { return nil }
        let uncommitted = changes.split(whereSeparator: \.isNewline).count
        // A repo with no remote is local on purpose; its commits aren't "unpushed".
        var unpushed = 0
        if !git(["remote"]).1.isEmpty, case let (0, out) = git(["rev-list", "--count", "HEAD", "--not", "--remotes"]) {
            unpushed = Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        let parts = [uncommitted > 0 ? "\(uncommitted) uncommitted" : nil, unpushed > 0 ? "\(unpushed) unpushed" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // A closed tab can skip SessionEnd; once nothing runs on its tty, the agent is gone.
    private func dropClosedTerminals() {
        let ttys = Set(sessions.filter { !$0.ended }.compactMap(\.tty))
        guard !ttys.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let (status, out) = ClaudeCLI.run("/bin/ps", ["-A", "-o", "tty="])
            guard status == 0 else { return }
            let live = Set(out.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
            let closed = ttys.subtracting(live)
            guard !closed.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.end(self.sessions.filter { !$0.ended && ($0.tty.map(closed.contains) ?? false) }.map(\.id))
            }
        }
    }

    // Sessions survive a restart (or an app update), so nothing waiting on you is lost. Private file, local only.
    static let savedPath = HookInstaller.home + "/.notchkeeper/sessions.json"

    func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.savedPath) { fm.createFile(atPath: Self.savedPath, contents: nil, attributes: [.posixPermissions: 0o600]) }
        try? data.write(to: URL(fileURLWithPath: Self.savedPath))
    }

    // Brings back yesterday's sessions; the ones still waiting on you open as a catch-up card.
    func restore() {
        guard let data = FileManager.default.contents(atPath: Self.savedPath),
              let saved = try? JSONDecoder().decode([Session].self, from: data) else { return }
        sessions = saved
        pruneStale()
        guard awayMinutes > 0 else { return }
        let waiting = sorted.filter { $0.state != .working && !$0.seen && $0.snoozedUntil == nil }
        guard let oldest = waiting.map(\.since).min() else { return }
        catchUp = CatchUp(since: oldest, items: waiting.map {
            CatchUp.Item(id: $0.id, state: $0.state, title: $0.title.isEmpty ? $0.repo : $0.title, detail: $0.question ?? $0.detail, files: [])
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if self?.catchUp?.since == oldest { self?.catchUp = nil }
        }
    }

    private func describe(_ name: String, _ event: [String: Any]) -> String? {
        let tool = Self.tool(event)
        let action = Self.target(event).map { "\(tool): \($0)" } ?? tool

        switch name {
        case "UserPromptSubmit": return "Thinking…"
        case "PreToolUse" where tool == "AskUserQuestion":
            let questions = (event["tool_input"] as? [String: Any])?["questions"] as? [[String: Any]]
            return "Asks: " + (questions?.first?["question"] as? String ?? "a question")
        case "PreToolUse": return action
        case "PermissionRequest": return "Wants \(action)"
        case "Notification": return event["message"] as? String
        case "Stop": return firstLine(event["last_assistant_message"] as? String) ?? "Your turn"
        default: return nil
        }
    }

    private func loadBranch(_ id: String, cwd: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let branch = Self.gitBranch(cwd)
            DispatchQueue.main.async {
                guard let i = self?.sessions.firstIndex(where: { $0.id == id }) else { return }
                self?.sessions[i].branch = branch
            }
        }
    }

    private func loadUnsaved(_ id: String, cwd: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let work = Self.unsavedWork(cwd)
            DispatchQueue.main.async {
                guard let i = self?.sessions.firstIndex(where: { $0.id == id }) else { return }
                self?.sessions[i].unsaved = work
            }
        }
    }

    // One chip per folder: on the agent there that was active last.
    func showsUnsaved(_ session: Session) -> Bool {
        guard session.unsaved != nil, session.state != .working else { return false }
        return !sessions.contains { $0.id != session.id && $0.cwd == session.cwd && $0.unsaved != nil && $0.lastSeen > session.lastSeen }
    }

    // Reads .git/HEAD directly instead of running git; worktrees have a .git file pointing at their real dir.
    static func gitBranch(_ cwd: String) -> String? {
        var dir = URL(fileURLWithPath: cwd)
        while dir.path != "/" {
            let git = dir.appendingPathComponent(".git")
            var gitDir = git
            if let link = try? String(contentsOf: git, encoding: .utf8), link.hasPrefix("gitdir: ") {
                gitDir = URL(fileURLWithPath: link.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: dir)
            }
            if let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) {
                let ref = head.trimmingCharacters(in: .whitespacesAndNewlines)
                return ref.hasPrefix("ref: refs/heads/") ? String(ref.dropFirst(16)) : String(ref.prefix(7))
            }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    // Titles can change, so this is re-read on every Stop. Transcripts can be large, hence the background queue.
    private func loadTitle(_ id: String, transcript path: String?, turnEnded: Bool) {
        guard let path = Self.claudeTranscript(path) else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let (title, firstPrompt, question, model) = Self.readTranscript(path)
            DispatchQueue.main.async {
                guard let self, let i = self.sessions.firstIndex(where: { $0.id == id }) else { return }
                // Background jobs get their worktree's folder name as a title; that one isn't yours, so a plugin may replace it.
                let folder = (self.sessions[i].cwd as NSString).lastPathComponent
                self.sessions[i].ownTitle = title == folder ? nil : title
                if let title = self.sessions[i].ownTitle ?? self.sessions[i].pluginTitle ?? firstPrompt { self.sessions[i].title = title }
                if let model { self.sessions[i].model = model }
                // A question box at the end of the turn means it's waiting on your answer.
                if self.sessions[i].state == .yourTurn, let question {
                    self.sessions[i].question = question
                    self.sessions[i].state = .needsYou
                    self.sessions[i].since = Date()
                    self.sessions[i].seen = false
                    self.alert(i)
                }
                if turnEnded && self.sessions[i].state == .yourTurn { self.sendQueued(i) }
            }
        }
    }

    // Title: the sidebar title (latest "customTitle" entry). Question: the last question box since the latest prompt.
    // Model: the one that wrote the last reply.
    private static func readTranscript(_ path: String) -> (title: String?, firstPrompt: String?, question: String?, model: String?) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return (nil, nil, nil, nil) }
        var title: String?
        var firstPrompt: String?
        var question: String?
        var model: String?
        for line in text.split(separator: "\n") {
            // Replies are the bulk of the file, so pull the model out without parsing JSON.
            if line.contains("\"type\":\"assistant\""), let r = line.range(of: "\"model\":\"") {
                let name = line[r.upperBound...].prefix { $0 != "\"" }
                if !name.hasPrefix("<") { model = String(name) }
            }
            let isTitle = line.contains("\"customTitle\"")
            let isQuestion = line.contains("wrap_up\"")
            // Tool results are logged as user entries too; they don't start a new turn.
            let isPrompt = line.contains("\"type\":\"user\"") && !line.contains("\"tool_result\"")
            guard isTitle || isQuestion || isPrompt,
                  let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if isTitle, let t = entry["customTitle"] as? String { title = t }
            let content = (entry["message"] as? [String: Any])?["content"]
            if isPrompt, let prompt = promptText(content) {
                firstPrompt = firstPrompt ?? prompt
                question = nil
            }
            if isQuestion { question = questionText(content) ?? question }
        }
        return (title, firstPrompt, question, model.map(modelName))
    }

    // "claude-opus-5-5" → "Opus 5.5"; drops date suffixes like "-20250929".
    private static func modelName(_ id: String) -> String {
        let parts = id.replacingOccurrences(of: "claude-", with: "").components(separatedBy: "-").filter { $0.count < 8 }
        guard let family = parts.first else { return id }
        let version = parts.dropFirst().joined(separator: ".")
        return family.capitalized + (version.isEmpty ? "" : " " + version)
    }

    private static func questionText(_ content: Any?) -> String? {
        let call = (content as? [[String: Any]])?.first { ($0["name"] as? String)?.hasSuffix("wrap_up") == true }
        return (call?["input"] as? [String: Any])?["ask"] as? String
    }

    private static func promptText(_ content: Any?) -> String? {
        let texts = (content as? String).map { [$0] }
            ?? (content as? [[String: Any]])?.compactMap { $0["text"] as? String } ?? []
        // Skip injected blocks like <system-reminder> or <command-name>.
        guard let text = texts.first(where: { !$0.hasPrefix("<") }) else { return nil }
        return text.split(separator: "\n").first.map { String($0.prefix(80)) }
    }

    private static func diff(_ input: [String: Any]) -> [(sign: Character, text: String)] {
        let edit = (input["edits"] as? [[String: Any]])?.first ?? input
        func lines(_ key: String) -> [String] {
            (edit[key] as? String ?? input[key] as? String ?? "").split(separator: "\n").map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        let removed = lines("old_string"), added = lines("new_string") + lines("content")
        return removed.prefix(3).map { ("-", $0) } + added.prefix(removed.isEmpty ? 5 : 3).map { ("+", $0) }
    }

    private func applyItem(_ id: String, _ event: [String: Any]) {
        guard id.hasPrefix("item:"), let title = event["title"] as? String else { return }
        if event["state"] as? String == "remove" { return sessions.removeAll { $0.id == id } }
        let state: SessionState = switch event["state"] as? String {
        case "needs-you": .needsYou
        case "done": .yourTurn
        default: .working
        }
        let source = (event["source"] as? String).flatMap { $0.range(of: "^[a-z0-9-]{1,20}$", options: .regularExpression) != nil ? $0 : nil } ?? "item"
        if !sessions.contains(where: { $0.id == id }) {
            var item = Session(id: id, repo: source, state: state, detail: "", lastSeen: Date())
            item.isItem = true
            sessions.append(item)
        }
        let i = sessions.firstIndex { $0.id == id }!
        let entered = sessions[i].state != state || sessions[i].detail.isEmpty
        if sessions[i].state != state { sessions[i].since = Date() }
        sessions[i].state = state
        sessions[i].title = String(title.prefix(120))
        sessions[i].detail = String((event["detail"] as? String ?? "").prefix(200))
        sessions[i].agent = source
        if let cwd = event["cwd"] as? String { sessions[i].cwd = cwd }
        sessions[i].lastSeen = Date()
        sessions[i].seen = false
        // Only web links; anything else (file:, custom schemes) could launch things.
        sessions[i].url = (event["url"] as? String).flatMap { $0.hasPrefix("https://") || $0.hasPrefix("http://") ? $0 : nil }
        if entered { ActivityLog.record(state.rawValue, sessions[i]) }
        if entered && state != .working { alert(i) }
    }

    // Events could name any file; only Claude's own transcripts are read.
    static func claudeTranscript(_ path: String?) -> String? {
        guard let path = (path as NSString?)?.standardizingPath, path.hasPrefix(NSHomeDirectory() + "/"), path.hasSuffix(".jsonl") else { return nil }
        let parts = path.dropFirst(NSHomeDirectory().count + 1).split(separator: "/")
        guard parts.count > 2, parts[0].hasPrefix(".claude"), parts[1] == "projects" else { return nil }
        return path
    }

    private func loadChat() {
        chat = []
        guard let session = replyTo, let path = sessions.first(where: { $0.id == session.id })?.transcript else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let lines = Chat.read(path)
            DispatchQueue.main.async { if self?.replyTo?.id == session.id { self?.chat = lines } }
        }
    }

    // Only "add an allow rule" suggestions, and only for this session: never saved to a settings file.
    private static func sessionRules(_ event: [String: Any]) -> [[String: Any]] {
        (event["permission_suggestions"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "addRules" && $0["behavior"] as? String == "allow" }
            .map { var rule = $0; rule["destination"] = "session"; return rule }
    }

    private static func tool(_ event: [String: Any]) -> String {
        (event["tool_name"] as? String ?? "").components(separatedBy: "__").last ?? ""
    }

    private static func target(_ event: [String: Any]) -> String? {
        let input = event["tool_input"] as? [String: Any] ?? [:]
        return input["command"] as? String
            ?? (input["file_path"] as? String).map { ($0 as NSString).lastPathComponent }
            ?? input["pattern"] as? String
            ?? input["description"] as? String
    }

    private func firstLine(_ text: String?) -> String? {
        let line = text?.split(separator: "\n").first.map(String.init)
        return line?.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "`", with: "")
    }
}
