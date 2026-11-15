import SwiftUI

// Renders README / site screenshots from the real views with sample sessions: ./tools/screenshots.sh
func demoStore() -> SessionStore {
    let store = SessionStore()
    let now = Date()
    func session(_ id: String, _ repo: String, _ title: String, _ state: SessionState, _ detail: String,
                 ago: TimeInterval, mode: String = "default", branch: String = "main", tty: String? = "ttys004") -> Session {
        var s = Session(id: id, repo: repo, title: title, branch: branch, tty: tty, term: tty == nil ? nil : "ghostty",
                        mode: mode, model: "Opus 5.5", effort: "high", state: state, detail: detail, lastSeen: now)
        s.since = now.addingTimeInterval(-ago)
        return s
    }
    store.sessions = [
        session("1", "api", "Rate limiter for public endpoints", .needsYou, "Wants Bash: npm run test:integration", ago: 260,
                branch: "rate-limits"),
        session("2", "web", "Checkout redesign", .yourTurn, "Done: the new checkout passes all 48 tests.", ago: 140,
                mode: "acceptEdits", branch: "checkout-v2", tty: nil),
        session("3", "ping", "Polish the notch UI", .working, "Edit: NotchView.swift", ago: 420, mode: "auto", branch: "polish"),
        session("4", "infra", "Migrate CI to arm runners", .working, "Bash: terraform plan -out ci.tfplan", ago: 75,
                branch: "arm-ci"),
    ]
    store.sessions[2].subagents = [Subagent(id: "a", type: "Explore", description: "Find hover handlers", detail: "Grep: onHover")]
    store.sounds = true
    store.quiet = false
    return store
}

@MainActor func render<V: View>(_ view: V, size: CGSize, to path: String) {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).transaction { $0.disablesAnimations = true })
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return print("failed \(path)") }
    try! png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

// The notch hangs from the top of a desktop-like backdrop.
struct Shot: View {
    let store: SessionStore
    let state: NotchState
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.16, green: 0.13, blue: 0.30), Color(red: 0.05, green: 0.18, blue: 0.24),
                                    Color(red: 0.03, green: 0.05, blue: 0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 0.55, green: 0.35, blue: 0.95).opacity(0.35), .clear],
                           center: .init(x: 0.2, y: 0.1), startRadius: 0, endRadius: 420)
            Rectangle().fill(.black.opacity(0.25)).frame(height: state.notch.height)
            NotchView(store: store, state: state).frame(width: state.windowSize.width, height: state.windowSize.height)
        }
        .frame(width: 760, height: max(height, state.windowSize.height), alignment: .top)
        .frame(width: 760, height: height, alignment: .top)
        .clipped()
    }
}

@main struct Screenshots {
@MainActor static func main() {
    let out = CommandLine.arguments.dropFirst().first ?? "docs/img"
    let notch = CGSize(width: 185, height: 32)

    func shot(_ name: String, height: CGFloat, configure: (SessionStore, NotchState) -> Void) {
        let store = demoStore()
        let state = NotchState()
        state.notch = notch
        configure(store, state)
        render(Shot(store: store, state: state, height: height), size: CGSize(width: 760, height: height), to: "\(out)/\(name).png")
    }

    shot("collapsed", height: 120) { _, _ in }
    shot("collapsed-working", height: 120) { store, _ in
        store.sessions = store.sessions.filter { $0.state == .working }
    }
    shot("no-notch", height: 120) { _, state in
        state.notch = CGSize(width: 0, height: 24)
    }
    shot("expanded", height: 390) { store, state in
        state.expanded = true
        state.hovered = "3"
    }
    shot("approval", height: 250) { store, _ in
        store.approvals = [Approval(sessionId: "1", agentId: nil, repo: "api", tool: "Bash", target: "npm run test:integration -- --runInBand",
                                    sessionRules: [["type": "addRules", "behavior": "allow", "destination": "session",
                                                    "rules": [["toolName": "Bash", "ruleContent": "npm run test:*"]]]],
                                    expires: Date().addingTimeInterval(19), reply: { _ in })]
    }
    shot("plan", height: 380) { store, _ in
        store.plan = PlanReview(sessionId: "3", repo: "ping", plan: """
            # Polish the notch UI
            ## Collapsed
            - Name the agent that needs you next to the notch, instead of a bare count
            - Show a soft **pulse** while agents just work
            ## Expanded
            1. Header with counts per state, plus **sound** and **quiet** toggles
            2. Rows show how long each agent has been waiting
            3. Approval card gains *Allow for session*
            """)
    }
}

}
