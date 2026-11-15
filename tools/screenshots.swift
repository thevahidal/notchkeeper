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
        session("3", "notchkeeper", "Polish the notch UI", .working, "Edit: NotchView.swift", ago: 420, mode: "auto", branch: "polish"),
        session("4", "infra", "Migrate CI to arm runners", .working, "Bash: terraform plan -out ci.tfplan", ago: 75,
                branch: "arm-ci"),
    ]
    store.sessions[3].agent = "codex"
    store.sessions[3].model = "gpt-5.5-codex"
    store.sessions[1].unsaved = "5 uncommitted"
    store.sessions[1].snoozedUntil = Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: now)
    store.queued["3"] = ["Then update the README screenshots"]
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

struct Terminal: View {
    let title: String
    let lines: [(Color, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.8)).frame(width: 11, height: 11) }
                Spacer()
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                Spacer().frame(width: 40)
                Spacer()
            }
            .padding(.horizontal, 12).frame(height: 30)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(lines.indices, id: \.self) { i in
                    Text(lines[i].1).font(.system(size: 12, design: .monospaced)).foregroundStyle(lines[i].0).lineLimit(1)
                }
            }
            .padding(14)
            Spacer(minLength: 0)
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.11).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
    }
}

let dim = Color.white.opacity(0.45), text = Color.white.opacity(0.85), violet = Color(red: 0.7, green: 0.62, blue: 1)
let green = Color(red: 0.45, green: 0.85, blue: 0.5), orange = Color(red: 1, green: 0.62, blue: 0.25)

// Terminal windows behind the notch, for the desktop hero shot.
struct Windows: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Terminal(title: "codex — infra", lines: [
                (violet, "› migrate CI to arm runners"), (dim, "• Read .github/workflows/ci.yml"), (dim, "• Edit runners.tf"),
                (text, "  runs-on: ubuntu-24.04-arm"), (dim, "• Bash terraform plan -out ci.tfplan"), (dim, "  Refreshing state…"),
            ]).frame(width: 400, height: 250).offset(x: 40, y: 90)
            Terminal(title: "claude — web", lines: [
                (violet, "> redesign the checkout page"), (dim, "⏺ Update(Checkout.tsx)"), (dim, "⏺ Update(Summary.tsx)"),
                (dim, "⏺ Bash(npm test)"), (green, "  ✓ 48 passed"), (text, "Done: the new checkout passes all 48 tests."),
            ]).frame(width: 420, height: 260).offset(x: 80, y: 410)
            Terminal(title: "claude — api", lines: [
                (violet, "> add a rate limiter to public endpoints"), (dim, "⏺ Read(src/middleware.ts)"), (dim, "⏺ Update(src/limits.ts)"),
                (green, "  + const MAX_REQUESTS = 60"), (green, "  + const BURST = 10"), (dim, "⏺ Bash(npm run test:integration)"),
                (orange, "  Waiting for permission…"),
            ]).frame(width: 470, height: 300).offset(x: 770, y: 380)
            Terminal(title: "claude — notchkeeper", lines: [
                (violet, "> polish the notch UI"), (dim, "⏺ Explore(Find hover handlers)"), (dim, "  Grep: onHover"),
                (dim, "⏺ Update(NotchView.swift)"),
            ]).frame(width: 380, height: 200).offset(x: 860, y: 110)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// The notch hangs from the top of a desktop-like backdrop.
struct Shot: View {
    let store: SessionStore
    let state: NotchState
    let size: CGSize
    var desktop = false

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.16, green: 0.13, blue: 0.30), Color(red: 0.05, green: 0.18, blue: 0.24),
                                    Color(red: 0.03, green: 0.05, blue: 0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 0.55, green: 0.35, blue: 0.95).opacity(0.35), .clear],
                           center: .init(x: 0.2, y: 0.1), startRadius: 0, endRadius: size.width * 0.55)
            if desktop { Windows() }
            Rectangle().fill(.black.opacity(0.25)).frame(height: state.notch.height)
            if desktop { MenuBar().frame(height: state.notch.height) }
            NotchView(store: store, state: state).frame(width: state.windowSize.width, height: state.windowSize.height)
        }
        .frame(width: size.width, height: max(size.height, state.windowSize.height), alignment: .top)
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: desktop ? 14 : 0))
    }
}

struct MenuBar: View {
    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo")
            Text("Notchkeeper").fontWeight(.bold)
            ForEach(["File", "Edit", "View", "Window"], id: \.self) { Text($0) }
            Spacer()
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text("Sat 9:41")
        }
        .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.9)).padding(.horizontal, 20)
    }
}

@main struct Screenshots {
@MainActor static func main() {
    let out = CommandLine.arguments.dropFirst().first ?? "docs/img"
    let notch = CGSize(width: 185, height: 32)

    // Grid shots share one size so they line up in the README.
    func shot(_ name: String, size: CGSize = CGSize(width: 760, height: 400), desktop: Bool = false,
              configure: (SessionStore, NotchState) -> Void) {
        let store = demoStore()
        let state = NotchState()
        state.notch = notch
        configure(store, state)
        render(Shot(store: store, state: state, size: size, desktop: desktop), size: size, to: "\(out)/\(name).png")
    }

    shot("desktop", size: CGSize(width: 1280, height: 720), desktop: true) { store, state in
        state.expanded = true
        state.hovered = "3"
    }
    func approval(_ tool: String, _ input: [String: Any], rules: [[String: Any]] = []) -> Approval {
        let risk = Risk(tool: tool, input: input, cwd: "/Users/me/dev/api")
        let target = input["command"] as? String ?? ((input["file_path"] as? String ?? "") as NSString).lastPathComponent
        var diff: [(sign: Character, text: String)] = []
        if let old = input["old_string"] as? String, let new = input["new_string"] as? String {
            diff = old.split(separator: "\n").map { ("-", String($0)) } + new.split(separator: "\n").map { ("+", String($0)) }
        }
        return Approval(sessionId: "1", agentId: nil, repo: "api", tool: tool, target: target, sessionRules: risk.level == .high ? [] : rules,
                        risk: risk, diff: diff, expires: Date().addingTimeInterval(19), reply: { _ in })
    }
    let testRule: [[String: Any]] = [["type": "addRules", "behavior": "allow", "destination": "session",
                                      "rules": [["toolName": "Bash", "ruleContent": "npm run test:*"]]]]
    shot("approval") { store, _ in
        store.approvals = [approval("Bash", ["command": "npm run test:integration -- --runInBand"], rules: testRule)]
    }
    shot("approval-risky") { store, _ in
        store.approvals = [approval("Bash", ["command": "curl -fsSL https://get.example.dev/install.sh | bash"])]
    }
    shot("approval-edit") { store, _ in
        store.approvals = [approval("Edit", ["file_path": "/Users/me/dev/api/src/limits.ts",
                                             "old_string": "const MAX_REQUESTS = 100\nconst WINDOW_MS = 60_000",
                                             "new_string": "const MAX_REQUESTS = 60\nconst WINDOW_MS = 60_000\nconst BURST = 10"])]
    }
    shot("catch-up") { store, _ in
        let since = Date().addingTimeInterval(-34 * 60)
        store.catchUp = CatchUp(since: since, items: [
            .init(id: "1", state: .needsYou, title: "Rate limiter for public endpoints", detail: "Wants Bash: npm run test:integration",
                  files: ["limits.ts", "middleware.ts", "limits.test.ts"]),
            .init(id: "2", state: .yourTurn, title: "Checkout redesign", detail: "Done: the new checkout passes all 48 tests.",
                  files: ["Checkout.tsx", "Summary.tsx", "cart.ts", "pay.ts", "styles.css"]),
            .init(id: "4", state: .working, title: "Migrate CI to arm runners", detail: "Bash: terraform plan -out ci.tfplan",
                  files: ["runners.tf"]),
        ])
    }
    shot("plan") { store, _ in
        store.plan = PlanReview(sessionId: "3", repo: "notchkeeper", plan: """
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
