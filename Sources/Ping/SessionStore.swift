import SwiftUI

enum SessionState {
    case working, needsYou, yourTurn
}

enum Mood {
    case idle, working, needsYou, yourTurn
}

struct Session: Identifiable {
    let id: String
    var repo: String
    var title = ""
    var branch: String?
    var tty: String?
    var term: String?
    // The desktop app's question box from the latest turn.
    var question: String?
    var seen = false
    var mode: String?
    var model: String?
    var effort: String?
    var subagents: [Subagent] = []
    var state: SessionState
    // When it entered the current state.
    var since = Date()
    var detail: String
    var lastSeen: Date
}

struct Subagent: Identifiable {
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
    let expires: Date
    let reply: EventServer.Reply
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
    @Published var sounds = UserDefaults.standard.object(forKey: "sounds") as? Bool ?? true {
        didSet { UserDefaults.standard.set(sounds, forKey: "sounds") }
    }
    // Collapsed notch stays dark until an agent needs you.
    @Published var quiet = UserDefaults.standard.bool(forKey: "quiet") {
        didSet { UserDefaults.standard.set(quiet, forKey: "quiet") }
    }
    @Published var replyTo: Session?
    @Published var draft = ""
    // First launch: ask before touching ~/.claude/settings.json.
    @Published var offerConnect = false
    @Published var connectError: String?
    static let approvalTimeout: TimeInterval = 29
    // Descriptions from Agent tool calls, waiting for their SubagentStart (which has the id).
    private var pendingAgents: [String: [String]] = [:]

    // Most urgent first, seen ones last, then most recent.
    var sorted: [Session] {
        func rank(_ s: Session) -> Int { s.seen ? 3 : s.state == .needsYou ? 0 : s.state == .yourTurn ? 1 : 2 }
        return sessions.sorted { (rank($0), $1.lastSeen) < (rank($1), $0.lastSeen) }
    }

    var mood: Mood {
        if sessions.contains(where: { $0.state == .needsYou }) { return .needsYou }
        if sessions.contains(where: { $0.state == .working }) { return .working }
        return sessions.contains { $0.state == .yourTurn && !$0.seen } ? .yourTurn : .idle
    }

    // The one session the collapsed notch names: the most urgent one still waiting on you.
    var headline: Session? {
        sorted.first { !$0.seen && $0.state != .working }
    }

    func jump(to session: Session) {
        Jump.to(session)
        markSeen(session.id)
    }

    // Only "your turn" can be seen; a question or approval still needs an answer.
    private func markSeen(_ id: String) {
        guard let i = sessions.firstIndex(where: { $0.id == id }), sessions[i].state == .yourTurn else { return }
        sessions[i].seen = true
    }

    func answer(_ approval: Approval, _ decision: String) {
        // Ignore clicks and hotkeys that land as the card pops up; you haven't read it yet.
        guard decision == "terminal" || Date().timeIntervalSince(approval.shown) > 0.7 else { return }
        if decision == "session" {
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
        } catch {
            connectError = error.localizedDescription
        }
    }

    func declineConnect() {
        offerConnect = false
        UserDefaults.standard.set(true, forKey: "declinedConnect")
    }

    func sendReply() {
        // Not typed (e.g. Claude has exited): take you to the tab instead.
        if let session = replyTo, !draft.isEmpty, !Jump.reply(session, draft) { Jump.to(session) }
        replyTo = nil
        draft = ""
    }

    func apply(_ event: [String: Any], reply: EventServer.Reply? = nil) {
        guard let id = event["session_id"] as? String, let name = event["hook_event_name"] as? String else { return }
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
            let approval = Approval(
                sessionId: id, agentId: agentId, repo: repo, tool: Self.tool(event), target: Self.target(event) ?? "",
                sessionRules: Self.sessionRules(event), expires: Date().addingTimeInterval(Self.approvalTimeout), reply: reply
            )
            approvals.append(approval)
            // The hook gives up after 30s, so drop the card just before that.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.approvalTimeout) { [weak self] in
                self?.approvals.removeAll { $0.id == approval.id }
            }
        }

        if name == "SessionEnd" {
            sessions.removeAll { $0.id == id }
            return
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
        if isNew || name == "Stop" { loadTitle(id, transcript: event["transcript_path"] as? String) }
        if isNew || name == "Stop", let cwd = event["cwd"] as? String { loadBranch(id, cwd: cwd) }
        if !sessions.contains(where: { $0.id == id }) {
            sessions.append(Session(id: id, repo: repo, state: state, detail: "", lastSeen: Date()))
        }
        let i = sessions.firstIndex { $0.id == id }!
        let entered = sessions[i].state != state || isNew
        if sessions[i].state != state { sessions[i].since = Date() }
        sessions[i].state = state
        sessions[i].detail = detail ?? sessions[i].detail
        if state == .working { sessions[i].question = nil }
        sessions[i].lastSeen = Date()
        // Only ping-hook.sh sends these; "??" means no terminal, i.e. the desktop app.
        if let tty = event["tty"] as? String {
            // It ends up inside an AppleScript, so accept only the "ttys012" shape.
            sessions[i].tty = tty.range(of: "^ttys[0-9]+$", options: .regularExpression) != nil ? tty : nil
            sessions[i].term = event["term"] as? String
        }
        if let mode = event["permission_mode"] as? String { sessions[i].mode = mode }
        if let effort = (event["effort"] as? [String: Any])?["level"] as? String { sessions[i].effort = effort }
        // A new event is unseen, unless it finished in the tab you're already looking at.
        sessions[i].seen = false
        // An AppleScript round trip, so only when it matters.
        let looking = (name == "Stop" || (entered && state != .working)) && Jump.isFrontmost(sessions[i])
        if name == "Stop" && looking { markSeen(id) }
        if entered && state != .working && !looking { chime(state) }
    }

    private var lastChime = Date.distantPast

    func chime(_ state: SessionState) {
        guard sounds, Date().timeIntervalSince(lastChime) > 2 else { return }
        lastChime = Date()
        NSSound(named: state == .needsYou ? "Ping" : "Pop")?.play()
    }

    // While something has needed you for a few minutes and you've stepped away, remind you once in a while.
    func remind() {
        let idle = [CGEventType.keyDown, .mouseMoved].map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
        let away = idle.min() ?? 0 > 60
        let stuck = sessions.contains { $0.state == .needsYou && Date().timeIntervalSince($0.since) > 180 }
        if away && stuck && Date().timeIntervalSince(lastChime) > 180 { chime(.needsYou) }
    }

    private func applySubagent(_ id: String, _ agentId: String, _ name: String, _ event: [String: Any]) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        if name == "SubagentStop" { return sessions[i].subagents.removeAll { $0.id == agentId } }
        if !sessions[i].subagents.contains(where: { $0.id == agentId }) {
            let description = pendingAgents[id]?.isEmpty == false ? pendingAgents[id]!.removeFirst() : ""
            sessions[i].subagents.append(Subagent(id: agentId, type: event["agent_type"] as? String ?? "Agent", description: description))
        }
        if name == "PreToolUse", let j = sessions[i].subagents.firstIndex(where: { $0.id == agentId }) {
            sessions[i].subagents[j].detail = describe(name, event) ?? ""
        }
    }

    // Fallback for sessions that crashed or were closed without a SessionEnd event.
    func pruneStale() {
        sessions.removeAll { $0.lastSeen < Date().addingTimeInterval(-30 * 60) }
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
    private func loadTitle(_ id: String, transcript path: String?) {
        // Events could name any file; only read Claude's own transcripts.
        let projects = NSHomeDirectory() + "/.claude/projects/"
        guard let path = (path as NSString?)?.standardizingPath, path.hasPrefix(projects), path.hasSuffix(".jsonl") else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let (title, question, model) = Self.readTranscript(path)
            DispatchQueue.main.async {
                guard let self, let i = self.sessions.firstIndex(where: { $0.id == id }) else { return }
                if let title { self.sessions[i].title = title }
                if let model { self.sessions[i].model = model }
                // A question box at the end of the turn means it's waiting on your answer.
                if self.sessions[i].state == .yourTurn, let question {
                    self.sessions[i].question = question
                    self.sessions[i].state = .needsYou
                    self.sessions[i].since = Date()
                    self.sessions[i].seen = false
                    self.chime(.needsYou)
                }
            }
        }
    }

    // Title: the sidebar title (latest "customTitle" entry), else the first prompt.
    // Question: the last question box since the latest prompt. Model: the one that wrote the last reply.
    private static func readTranscript(_ path: String) -> (title: String?, question: String?, model: String?) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return (nil, nil, nil) }
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
        return (title ?? firstPrompt, question, model.map(modelName))
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
