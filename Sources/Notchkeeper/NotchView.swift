import SwiftUI

struct NotchView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var state: NotchState

    var body: some View {
        let approval = store.approvals.first
        let card = state.cardHeight(store) != nil
        let size = state.size(store)
        let radius: CGFloat = state.expanded || card ? 24 : 10
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)
        let fade = AnyTransition.opacity.animation(.easeOut(duration: 0.2).delay(0.12))

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(.black)
                if let approval {
                    ApprovalCard(store: store, approval: approval, title: title(approval.sessionId), notchHeight: state.notch.height) {
                        store.answer(approval, $0)
                    }
                    .transition(fade)
                } else if store.offerConnect {
                    ConnectCard(store: store, notchHeight: state.notch.height).transition(fade)
                } else if store.newAgent != nil {
                    NewAgentCard(store: store, notchHeight: state.notch.height).transition(fade)
                } else if let session = store.replyTo {
                    ReplyCard(store: store, session: session, notchHeight: state.notch.height).transition(fade)
                } else if let plan = store.plan {
                    PlanCard(store: store, plan: plan, title: title(plan.sessionId), notchHeight: state.notch.height)
                        .transition(fade)
                } else if let catchUp = store.catchUp {
                    CatchUpCard(store: store, catchUp: catchUp, notchHeight: state.notch.height).transition(fade)
                } else if state.expanded {
                    expanded.transition(fade)
                } else if state.showsEars(store) {
                    collapsed.transition(.opacity.animation(.easeOut(duration: 0.12)))
                }
                if store.mood != .idle && (state.showsEars(store) || card || state.expanded) { glow(width: size.width) }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .overlay(shape.stroke(.white.opacity(state.expanded || card ? 0.07 : 0), lineWidth: 1))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: state.expanded)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: store.sessions.map(\.id))
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: state.filter)
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: approval?.id)
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: store.replyTo?.id)
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: store.plan?.sessionId)
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: store.catchUp?.since)
        .animation(.spring(response: 0.42, dampingFraction: 0.74), value: store.newAgent != nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.headline?.id)
    }

    private func title(_ sessionId: String) -> String? {
        store.sessions.first { $0.id == sessionId }.flatMap { $0.title.isEmpty ? nil : $0.title }
    }

    // Left: one dot per agent (or counts). Right: which agent needs you, by name, or a pulse while they work.
    private var collapsed: some View {
        let sessions = store.sorted
        let ear = state.earWidth(store)
        // Seen sessions are parked: they don't show up in the counts.
        let counts = [SessionState.needsYou, .yourTurn, .working]
            .map { s in (s, sessions.filter { $0.state == s && !$0.seen }.count) }
            .filter { $0.1 > 0 }

        return HStack(spacing: 0) {
            HStack(spacing: 5) {
                if sessions.count > state.maxDots {
                    ForEach(counts, id: \.0) { s, n in
                        HStack(spacing: 3) {
                            Orb(state: s, size: 6)
                            Text("\(n)").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Palette.orb(s))
                        }
                    }
                } else {
                    ForEach(sessions) { Orb(state: $0.state, seen: $0.seen).transition(.scale.combined(with: .opacity)) }
                }
            }
            .frame(width: ear)
            Spacer()
            Group {
                if let headline = store.headline {
                    HStack(spacing: 4) {
                        Image(systemName: headline.state == .needsYou ? "hand.raised.fill" : "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text(headline.repo)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(Palette.orb(headline.state))
                    .padding(.horizontal, 6)
                    .id(headline.id)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                } else if store.sessions.contains(where: { $0.state == .working }) {
                    Pulse()
                }
            }
            .frame(width: ear)
        }
        .frame(height: state.notch.height)
    }

    private var expanded: some View {
        let sessions = state.visible(store)

        return VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: state.notch.height + 2)
            header.frame(height: state.headerHeight)
            let rows = VStack(alignment: .leading, spacing: 0) { ForEach(sessions) { row($0) } }
            // Scroll only when the rows don't fit, so a short list doesn't bounce.
            Group {
                if sessions.reduce(0, { $0 + state.height(of: $1) }) > state.maxListHeight {
                    ScrollView(showsIndicators: false) { rows }
                } else {
                    rows
                }
            }
            .frame(height: state.listHeight(sessions), alignment: .top)
        }
        .padding(.horizontal, 12)
    }

    private var header: some View {
        let counts: [(SessionState, String)] = [(.needsYou, "need you"), (.working, "working"), (.yourTurn, "done")]
        return HStack(spacing: 4) {
            ForEach(counts, id: \.0) { s, label in
                let n = store.sessions.filter { $0.state == s }.count
                if n > 0 {
                    let on = state.filter == s
                    Button { state.filter = on ? nil : s } label: {
                        HStack(spacing: 5) {
                            Orb(state: s, size: 5)
                            Text("\(n) \(s == .needsYou && n == 1 ? "needs you" : label)")
                        }
                        .foregroundStyle(s == .working ? .white.opacity(0.5) : Palette.orb(s))
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(.white.opacity(on ? 0.14 : 0), in: Capsule())
                        .opacity(state.filter == nil || on ? 1 : 0.45)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(on ? "Show all agents" : "Show only these")
                }
            }
            Spacer()
            if store.sessions.contains(where: { $0.state == .yourTurn }) {
                HeaderToggle(on: false, symbol: "checkmark.circle", help: "Clear finished agents") { store.clearFinished() }
            }
            HeaderToggle(on: false, symbol: "plus", help: "Start a background agent") { store.openNewAgent() }
            HeaderToggle(on: store.sounds, symbol: store.sounds ? "speaker.wave.2.fill" : "speaker.slash.fill",
                         help: store.sounds ? "Sounds on" : "Sounds off") { store.sounds.toggle() }
            HeaderToggle(on: store.quiet, symbol: "moon.fill",
                         help: store.quiet ? "Quiet: the notch lights up only when an agent needs you" : "Quiet mode off") {
                store.quiet.toggle()
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 8)
    }

    private func row(_ session: Session) -> some View {
        let hovered = state.hovered == session.id
        return HStack(alignment: .top, spacing: 10) {
            StateBadge(session: session).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 6) {
                    Text(session.title.isEmpty ? session.repo : session.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(session.seen ? 0.5 : 0.95))
                        .lineLimit(1)
                    if !session.subagents.isEmpty {
                        Text("⑂ \(session.subagents.count)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.working[1])
                    }
                    if let agent = session.agent { Tag(text: agent, color: .white.opacity(0.6)) }
                    if session.background { Tag(text: "bg", color: Palette.plan) }
                    if let until = session.snoozedUntil {
                        Tag(text: "zz " + until.formatted(date: .omitted, time: .shortened), color: .white.opacity(0.5))
                    }
                    if let n = store.queued[session.id]?.count { Tag(text: "\(n) queued", color: Palette.working[1]) }
                    Spacer(minLength: 8)
                    if let mode = session.mode { ModeBadge(mode: mode) }
                    Elapsed(session: session)
                }
                HStack(spacing: 8) {
                    detail(session)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    Text(meta(session))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.32))
                        .lineLimit(1)
                }
                ForEach(session.subagents) { agent in
                    Text("↳ \(agent.type)").foregroundColor(Palette.working[1])
                        + Text([agent.description, agent.detail].filter { !$0.isEmpty }.map { " · " + $0 }.joined())
                        .foregroundColor(.white.opacity(0.45))
                }
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(height: state.subagentHeight - 4, alignment: .leading)
            }
            // On hover only, so rows stay calm.
            if session.state != .working && hovered {
                SnoozeMenu(store: store, session: session, hovered: hovered).padding(.top, 4)
            }
            if hovered {
                Button { store.dismiss(session.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 26, height: 26)
                        .background(.white.opacity(0.16), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close: hide until it does something new")
                .padding(.top, 4)
            }
            if Jump.canReply(session) {
                Button { store.replyTo = session } label: {
                    Image(systemName: session.state == .working ? "text.badge.plus" : "arrowshape.turn.up.left.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(hovered ? 0.95 : 0.6))
                        .frame(width: 26, height: 26)
                        .background(.white.opacity(hovered ? 0.16 : 0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help(session.state == .working ? "Queue a follow-up for when it finishes" : "Reply")
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: state.height(of: session), maxHeight: state.height(of: session), alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(hovered ? 0.07 : 0))
                .padding(.vertical, 2)
        )
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { state.hovered = session.id } else if state.hovered == session.id { state.hovered = nil }
        }
        .onTapGesture { store.jump(to: session) }
        .help(Jump.appId(session) == nil ? "" : "Go to this agent")
    }

    // Where it runs: branch (or folder), then model and effort.
    private func meta(_ session: Session) -> String {
        let place = session.title.isEmpty ? session.branch : [session.repo, session.branch].compactMap { $0 }.joined(separator: " ⎇ ")
        return [place, session.model, session.effort].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func detail(_ session: Session) -> Text {
        if let question = session.question { return Text(question).foregroundColor(.white.opacity(0.85)) }
        return Text(session.detail)
    }

    private func glow(width: CGFloat) -> some View {
        let mood = store.mood
        let colors = Palette.glow(mood)
        return ZStack {
            Glow(colors: colors, flows: mood == .working, breatheRate: Palette.breatheRate(mood))
                .frame(height: 8).blur(radius: 6).opacity(0.9)
            Glow(colors: colors, flows: mood == .working, breatheRate: Palette.breatheRate(mood))
                .frame(height: 2).blur(radius: 0.5)
        }
        .frame(width: width * 0.8)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .transition(.opacity)
    }
}

enum Palette {
    static let working = [Color(red: 0.50, green: 0.47, blue: 0.87), Color(red: 0.36, green: 0.79, blue: 0.65)]
    static let needsYou = [Color(red: 0.96, green: 0.62, blue: 0.15), Color(red: 0.96, green: 0.45, blue: 0.40)]
    static let yourTurn = [Color(red: 0.55, green: 0.80, blue: 0.36), Color(red: 0.36, green: 0.79, blue: 0.65)]
    static let danger = Color(red: 0.98, green: 0.36, blue: 0.36)
    static let plan = Color(red: 0.45, green: 0.65, blue: 0.98)

    static func glow(_ mood: Mood) -> [Color] {
        switch mood {
        case .needsYou: needsYou
        case .yourTurn: yourTurn
        case .working, .idle: working
        }
    }

    // Needs you pulses fast; your turn breathes slowly.
    static func breatheRate(_ mood: Mood) -> Double {
        switch mood {
        case .needsYou: 4.5
        case .yourTurn: 1.6
        case .working, .idle: 0
        }
    }

    static func orb(_ state: SessionState) -> Color {
        switch state {
        case .working: Color(red: 0.69, green: 0.66, blue: 0.95)
        case .needsYou: needsYou[0]
        case .yourTurn: yourTurn[0]
        }
    }
}

// A light strip that flows sideways (working) or breathes (waiting on you).
// TimelineView instead of @State: this toolchain lacks SwiftUI's macro plugins.
struct Glow: View {
    let colors: [Color]
    let flows: Bool
    let breatheRate: Double

    var body: some View {
        TimelineView(.animation(paused: !flows && breatheRate == 0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let phase = CGFloat(t.truncatingRemainder(dividingBy: 2.4) / 2.4)
                // Two repeats of the pattern so sliding by one width loops seamlessly.
                LinearGradient(colors: colors + colors + [colors[0]], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 2)
                    .offset(x: flows ? -geo.size.width * phase : 0)
            }
            .mask(LinearGradient(colors: [.clear, .white, .white, .clear], startPoint: .leading, endPoint: .trailing))
            .opacity(breatheRate > 0 ? 0.35 + 0.65 * (0.5 + 0.5 * sin(t * breatheRate)) : 1)
        }
    }
}

struct Orb: View {
    let state: SessionState
    // Seen "your turn" sessions sit still and dim.
    var seen = false
    var size: CGFloat = 7

    var body: some View {
        let color = Palette.orb(state).opacity(seen ? 0.4 : 1)
        let rate = seen ? 0 : state == .needsYou ? 4.0 : state == .yourTurn ? 1.6 : 0
        TimelineView(.animation(paused: rate == 0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.9), radius: 3)
                .opacity(rate > 0 ? 0.65 + 0.35 * sin(t * rate) : 1)
        }
    }
}

// Three bars rising and falling: agents are busy, nothing needs you.
struct Pulse: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<3) { i in
                    Capsule()
                        .fill(Palette.orb(.working))
                        .frame(width: 2.5, height: 4 + 6 * (0.5 + 0.5 * sin(t * 5 + Double(i) * 1.1)))
                }
            }
            .frame(height: 11)
            .shadow(color: Palette.orb(.working).opacity(0.7), radius: 2)
        }
    }
}

// The app the agent runs in, ringed in its state's color.
struct StateBadge: View {
    let session: Session

    var body: some View {
        let color = Palette.orb(session.state).opacity(session.seen ? 0.35 : 1)
        ZStack(alignment: .topLeading) {
            AppIcon(session: session)
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.55), lineWidth: 1))
                .overlay(alignment: .bottomTrailing) {
                    if !session.isItem && session.tty != nil { EnvIcon(session: session).offset(x: 4, y: 4) }
                }
            Orb(state: session.state, seen: session.seen, size: 8)
                .padding(2)
                .background(.black, in: Circle())
                .offset(x: -4, y: -4)
        }
    }
}

// "waiting 4m" for agents blocked on you, "2m ago" when done, plain time while working.
struct Elapsed: View {
    let session: Session

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let text = Self.short(context.date.timeIntervalSince(session.since))
            let (label, color): (String, Color) = switch session.state {
            case .needsYou: ("waiting \(text)", Palette.needsYou[0])
            case .yourTurn: ("\(text) ago", .white.opacity(0.4))
            case .working: (text, .white.opacity(0.4))
            }
            Text(label)
                .font(.system(size: 11, weight: session.state == .needsYou ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(color)
                .fixedSize()
        }
    }

    static func short(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        if s < 60 { return "now" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h \(s % 3600 / 60)m"
    }
}

struct HeaderToggle: View {
    let on: Bool
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(on ? .white : .white.opacity(0.4))
                .frame(width: 24, height: 20)
                .background(.white.opacity(on ? 0.14 : 0.05), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct ApprovalCard: View {
    @ObservedObject var store: SessionStore
    let approval: Approval
    let title: String?
    let notchHeight: CGFloat
    let onAnswer: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Color.clear.frame(height: notchHeight - 8)
            HStack(spacing: 10) {
                Image(systemName: Self.symbol(approval.tool))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 24, height: 24)
                    .background(approval.risk.level == .high ? Palette.danger : Palette.needsYou[0], in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title ?? approval.repo)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("wants to use \(approval.tool)" + (title == nil ? "" : " · \(approval.repo)"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
                if approval.risk.level != .low { RiskBadge(level: approval.risk.level) }
                Countdown(expires: approval.expires)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(approval.target.isEmpty ? approval.tool : approval.target)
                    .foregroundStyle(.white.opacity(approval.diff.isEmpty ? 0.92 : 0.5))
                    .lineLimit(approval.diff.isEmpty ? 2 : 1)
                    .truncationMode(.middle)
                ForEach(Array(approval.diff.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: "\(line.sign) \(line.text)")
                        .foregroundStyle(line.sign == "-" ? Palette.danger.opacity(0.9) : Palette.yourTurn[0])
                        .lineLimit(1)
                        .frame(height: 13, alignment: .leading)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(approval.risk.level == .high ? Palette.danger.opacity(0.5) : .clear))
            if approval.risk.level != .low {
                Label(approval.risk.reasons.joined(separator: " · "), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(approval.risk.level == .high ? Palette.danger : Palette.needsYou[0])
                    .lineLimit(1)
            }
            if !approval.sessionRules.isEmpty {
                Text("For session: always allow " + rules)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if store.feedbackFor == approval.id {
                FeedbackField(store: store) { onAnswer("deny-message") }
            } else {
            HStack(spacing: 6) {
                // On a risky call, Allow stops being the inviting button.
                if approval.risk.level == .high {
                    CardButton(title: "Allow anyway", hint: "⌥Y", fill: Palette.danger.opacity(0.18), text: Palette.danger) { onAnswer("allow") }
                } else {
                    CardButton(title: "Allow", hint: "⌥Y", fill: Palette.yourTurn[0], text: .black) { onAnswer("allow") }
                }
                if !approval.sessionRules.isEmpty {
                    CardButton(title: "For session", fill: Palette.yourTurn[0].opacity(0.2), text: Palette.yourTurn[0]) {
                        onAnswer("session")
                    }
                }
                CardButton(title: "Deny", hint: "⌥N", fill: .white.opacity(0.12), text: .white) { onAnswer("deny") }
                CardButton(title: "Tell Claude…", fill: .clear, text: .white.opacity(0.7)) { store.feedbackFor = approval.id }
                    .help("Deny and say why, or what to do instead")
                Spacer()
                CardButton(title: "Terminal", fill: .clear, text: .white.opacity(0.55)) { onAnswer("terminal") }
            }
            }
        }
        .padding(.horizontal, 18)
    }

    private var rules: String {
        approval.sessionRules.flatMap { $0["rules"] as? [[String: Any]] ?? [] }
            .map { rule in
                let tool = rule["toolName"] as? String ?? ""
                return (rule["ruleContent"] as? String).map { "\(tool)(\($0))" } ?? tool
            }
            .joined(separator: ", ")
    }

    private static func symbol(_ tool: String) -> String {
        switch tool {
        case "Bash": "terminal.fill"
        case "Edit", "Write", "MultiEdit", "NotebookEdit": "pencil"
        case "WebFetch", "WebSearch": "globe"
        case "Read", "Glob", "Grep": "doc.text.magnifyingglass"
        default: "hand.raised.fill"
        }
    }
}

// Only shown when something matched; no badge never means "safe".
struct RiskBadge: View {
    let level: Risk.Level

    var body: some View {
        let (label, color) = level == .high ? ("Risky", Palette.danger) : ("Check", Palette.needsYou[0])
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(color.opacity(0.16), in: Capsule())
    }
}

struct CardButton: View {
    let title: String
    var hint: String?
    let fill: Color
    let text: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 12, weight: .semibold))
                if let hint { Text(hint).font(.system(size: 10, weight: .medium)).opacity(0.55) }
            }
            .foregroundStyle(text)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// Claude ignores hook answers to ExitPlanMode, so this only shows the plan and takes you to where you approve it.
struct PlanCard: View {
    @ObservedObject var store: SessionStore
    let plan: PlanReview
    let title: String?
    let notchHeight: CGFloat

    var body: some View {
        let session = store.sessions.first { $0.id == plan.sessionId }
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: notchHeight - 8)
            HStack(spacing: 10) {
                Image(systemName: "list.bullet.clipboard.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 24, height: 24)
                    .background(Color(red: 0.45, green: 0.65, blue: 0.98), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Plan ready").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Text(title.map { "\($0) · \(plan.repo)" } ?? plan.repo)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
            }
            let lines = VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(plan.plan.split(separator: "\n", omittingEmptySubsequences: true).enumerated()), id: \.offset) {
                    Markdown.line(String($0.element))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            ViewThatFits(in: .vertical) {
                lines.frame(maxHeight: .infinity, alignment: .top)
                ScrollView(showsIndicators: false) { lines }
            }
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 6) {
                if let session {
                    CardButton(title: "Review and approve", fill: Color(red: 0.45, green: 0.65, blue: 0.98), text: .black) {
                        store.plan = nil
                        store.jump(to: session)
                    }
                }
                CardButton(title: "Later", fill: .white.opacity(0.12), text: .white) { store.plan = nil }
            }
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 18)
    }
}

// "While you were away": what each agent did, and who's waiting, the moment you're back.
struct CatchUpCard: View {
    @ObservedObject var store: SessionStore
    let catchUp: CatchUp
    let notchHeight: CGFloat

    var body: some View {
        let shown = catchUp.items.prefix(4)
        VStack(alignment: .leading, spacing: 8) {
            Color.clear.frame(height: notchHeight - 8)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("While you were away").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text(Elapsed.short(Date().timeIntervalSince(catchUp.since)))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text(summary).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            }
            ForEach(shown) { item in
                HStack(alignment: .top, spacing: 10) {
                    Orb(state: item.state).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(verb(item.state))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(item.state == .working ? .white.opacity(0.5) : Palette.orb(item.state))
                        }
                        Text(files(item).map { "\($0) · " + item.detail } ?? item.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                .frame(height: 36, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture {
                    store.catchUp = nil
                    if let session = store.sessions.first(where: { $0.id == item.id }) { store.jump(to: session) }
                }
            }
            HStack {
                if catchUp.items.count > shown.count {
                    Text("and \(catchUp.items.count - shown.count) more").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                CardButton(title: "Got it", fill: .white.opacity(0.12), text: .white) { store.catchUp = nil }
            }
        }
        .padding(.horizontal, 18)
    }

    private var summary: String {
        let need = catchUp.items.filter { $0.state == .needsYou }.count
        let done = catchUp.items.filter { $0.state == .yourTurn }.count
        return [need > 0 ? "\(need) need you" : nil, done > 0 ? "\(done) done" : nil].compactMap { $0 }.joined(separator: " · ")
    }

    private func verb(_ state: SessionState) -> String {
        switch state {
        case .needsYou: "needs you"
        case .yourTurn: "finished"
        case .working: "still working"
        }
    }

    // "Edited Risk.swift, NotchView.swift +2"
    private func files(_ item: CatchUp.Item) -> String? {
        guard !item.files.isEmpty else { return nil }
        let names = item.files.prefix(2).joined(separator: ", ")
        return "Edited " + names + (item.files.count > 2 ? " +\(item.files.count - 2)" : "")
    }
}

// Just enough Markdown for a plan: headings, bullets, numbered steps and inline styles.
enum Markdown {
    static func line(_ raw: String) -> some View {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let level = trimmed.prefix { $0 == "#" }.count
        let indent = CGFloat(raw.prefix { $0 == " " }.count / 2) * 12
        var body = level > 0 ? String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces) : trimmed
        var bullet: String?
        if body.hasPrefix("- ") || body.hasPrefix("* ") {
            bullet = "•"
            body = String(body.dropFirst(2))
        } else if let r = body.range(of: "^[0-9]+\\. ", options: .regularExpression) {
            bullet = String(body[r]).trimmingCharacters(in: .whitespaces)
            body = String(body[r.upperBound...])
        }
        let text = (try? AttributedString(markdown: body)) ?? AttributedString(body)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let bullet { Text(bullet).foregroundStyle(.white.opacity(0.4)) }
            Text(text)
                .foregroundStyle(.white.opacity(level > 0 ? 0.95 : 0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: level == 0 ? 12 : level == 1 ? 14 : 13, weight: level > 0 ? .semibold : .regular))
        .padding(.leading, indent)
        .padding(.top, level > 0 ? 4 : 0)
    }
}

// The agent: Claude's app icon, or a letter for Codex and Gemini.
struct AppIcon: View {
    let session: Session

    var body: some View {
        Group {
            if session.isItem {
                Image(systemName: "bolt.fill").resizable().scaledToFit()
            } else if let agent = session.agent.flatMap(Agent.init) {
                Text(agent.title.prefix(1)).font(.system(size: 14, weight: .bold, design: .rounded))
            } else {
                (Self.icon("com.anthropic.claudefordesktop") ?? Image(systemName: "sparkle")).resizable().scaledToFit()
            }
        }
        .frame(width: 18, height: 18)
        .foregroundStyle(.white.opacity(0.6))
    }

    private static var cache: [String: Image] = [:]

    // Drawn into a plain 8-bit sRGB bitmap: the system's extended-range icons wash out the whole view around them.
    static func icon(_ bundleId: String) -> Image? {
        if let cached = cache[bundleId] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx else { return nil }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSWorkspace.shared.icon(forFile: url.path).draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
        NSGraphicsContext.current = nil
        guard let cg = ctx.makeImage() else { return nil }
        let image = Image(decorative: cg, scale: 2)
        cache[bundleId] = image
        return image
    }
}

// The terminal a CLI session runs in.
struct EnvIcon: View {
    let session: Session

    var body: some View {
        (Jump.appId(session).flatMap(AppIcon.icon) ?? Image(systemName: "terminal"))
            .resizable()
            .scaledToFit()
            .frame(width: 13, height: 13)
            .foregroundStyle(.white.opacity(0.8))
            .background(.black, in: RoundedRectangle(cornerRadius: 3))
    }
}

// The permission mode; bypass is red because that agent runs without asking.
struct ModeBadge: View {
    let mode: String

    var body: some View {
        let (label, color): (String, Color) = switch mode {
        case "default": ("ask", .white.opacity(0.55))
        case "auto": ("auto", Palette.working[1])
        case "plan": ("plan", Color(red: 0.45, green: 0.65, blue: 0.98))
        case "acceptEdits": ("edits", Palette.working[0])
        case "bypassPermissions": ("bypass", Color(red: 0.95, green: 0.38, blue: 0.38))
        default: (mode, .white.opacity(0.55))
        }
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(color.opacity(0.16), in: Capsule())
    }
}

struct ConnectCard: View {
    @ObservedObject var store: SessionStore
    let notchHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear.frame(height: notchHeight - 6)
            Text(store.renamedFromPing ? "Ping is now Notchkeeper" : "Connect Notchkeeper to Claude Code?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(store.connectError ?? (store.renamedFromPing
                ? "Swap Ping's hooks in ~/.claude/settings.json for Notchkeeper's (a backup is kept). Until then, agents won't show up."
                : "Adds Notchkeeper's hooks to ~/.claude/settings.json (a backup is kept). Events stay on this Mac."))
                .font(.system(size: 12))
                .foregroundStyle(store.connectError == nil ? .white.opacity(0.6) : Palette.needsYou[0])
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                CardButton(title: store.renamedFromPing ? "Update" : "Connect", fill: Palette.yourTurn[0], text: .black) { store.connect() }
                CardButton(title: "Not now", fill: .white.opacity(0.14), text: .white) { store.declineConnect() }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 18)
    }
}

// "Remind me later" for an agent you can't deal with right now; it comes back with a ping.
struct SnoozeMenu: View {
    @ObservedObject var store: SessionStore
    let session: Session
    let hovered: Bool

    var body: some View {
        Menu {
            Button("In 15 minutes") { store.snooze(session, until: Date().addingTimeInterval(15 * 60)) }
            Button("In 1 hour") { store.snooze(session, until: Date().addingTimeInterval(3600)) }
            Button("Tomorrow at 9") { store.snooze(session, until: Self.tomorrowMorning) }
        } label: {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(hovered ? 0.9 : 0.5))
                .frame(width: 26, height: 26)
                .background(.white.opacity(hovered ? 0.16 : 0.08), in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Remind me later")
    }

    private static var tomorrowMorning: Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

// The conversation so far: your messages on the right, Claude's on the left, tool calls as quiet one-liners.
struct ChatView: View {
    let lines: [ChatLine]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(lines) { line in
                        switch line.role {
                        case .you:
                            Text(line.text)
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                                .lineLimit(4)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Palette.plan.opacity(0.28), in: RoundedRectangle(cornerRadius: 11))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.leading, 60)
                        case .claude:
                            Text((try? AttributedString(markdown: line.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                                 ?? AttributedString(line.text))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.trailing, 30)
                        case .tool:
                            Text("⏺ " + line.text)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.35))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
            }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: lines.count) { proxy.scrollTo("end", anchor: .bottom) }
        }
        .frame(maxHeight: .infinity)
        .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .init(x: 0.5, y: 0.12)))
    }
}

struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .frame(height: 14)
            .background(color.opacity(0.16), in: Capsule())
    }
}

// Deny, with a message Claude reads instead of a bare "no".
struct FeedbackField: View {
    @ObservedObject var store: SessionStore
    let send: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("Deny and tell Claude what to do instead…", text: $store.feedback)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(.white.opacity(0.08), in: Capsule())
                .focused($focused)
                .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true } }
                .onSubmit(send)
                .onExitCommand { store.feedbackFor = nil; store.feedback = "" }
            CardButton(title: "Deny and send", fill: .white.opacity(0.14), text: .white, action: send)
        }
    }
}

// Starts `claude --bg` in a folder, optionally in its own git worktree, so agents don't trip over each other.
struct NewAgentCard: View {
    @ObservedObject var store: SessionStore
    let notchHeight: CGFloat
    @FocusState private var focused: Bool

    var body: some View {
        let draft = store.newAgent ?? NewAgent(folder: NSHomeDirectory(), worktree: false)
        let isRepo = SessionStore.gitBranch(draft.folder) != nil
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: notchHeight - 8)
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 24, height: 24)
                    .background(Palette.plan, in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text("New background agent").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Text("Runs on its own, no terminal needed")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Text("esc cancel").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach(store.recentFolders, id: \.self) { folder in
                        Button((folder as NSString).abbreviatingWithTildeInPath) { store.openNewAgent(in: folder) }
                    }
                    Divider()
                    Button("Choose…") { chooseFolder() }
                } label: {
                    Label((draft.folder as NSString).lastPathComponent, systemImage: "folder.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(.white.opacity(0.08), in: Capsule())
                Toggle(isOn: Binding(get: { draft.worktree && isRepo }, set: { store.newAgent?.worktree = $0 })) {
                    Text("Own worktree").font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!isRepo)
                .help(isRepo ? "A separate checkout and branch, so parallel agents don't collide" : "Not a git repository")
                .foregroundStyle(.white.opacity(isRepo ? 0.8 : 0.35))
                Spacer()
            }
            TextField("What should it do?", text: Binding(get: { draft.prompt }, set: { store.newAgent?.prompt = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(9)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                .focused($focused)
                .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true } }
                .onSubmit { store.launchAgent() }
                .onExitCommand { store.newAgent = nil }
            HStack(spacing: 6) {
                CardButton(title: draft.busy ? "Starting…" : "Start", hint: "↩", fill: Palette.plan, text: .black) { store.launchAgent() }
                CardButton(title: "Cancel", fill: .white.opacity(0.12), text: .white) { store.newAgent = nil }
                if let error = draft.error {
                    Text(error).font(.system(size: 11)).foregroundStyle(Palette.danger).lineLimit(2)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 18)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: store.newAgent?.folder ?? NSHomeDirectory())
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { store.openNewAgent(in: url.path) }
    }
}

struct ReplyCard: View {
    @ObservedObject var store: SessionStore
    let session: Session
    let notchHeight: CGFloat
    @FocusState private var focused: Bool

    private var working: Bool { store.sessions.first { $0.id == session.id }?.state == .working }
    private var queuedNote: String {
        store.queued[session.id].map { " \($0.count) already queued." } ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: notchHeight - 6)
            HStack(spacing: 8) {
                Orb(state: session.state)
                Text(session.title.isEmpty ? session.repo : session.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Text(working ? "↩ queue   esc cancel" : "↩ send   esc cancel")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            if !store.chat.isEmpty { ChatView(lines: store.chat) }
            Text(working ? "Still working. Your message is sent when this turn ends, unless it ends with a question." + queuedNote
                         : session.question ?? (store.chat.isEmpty ? session.detail : ""))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(2)
            TextField(working ? "Queue a follow-up…" : "Reply…", text: $store.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(9)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                .focused($focused)
                // The panel becomes key on the next hover tick, so focus just after that.
                .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true } }
                .onSubmit { store.sendReply() }
                .onExitCommand { store.draft = ""; store.replyTo = nil }
        }
        .padding(.horizontal, 18)
    }
}

// A ring that empties as the hook's 30s wait runs out.
struct Countdown: View {
    let expires: Date

    var body: some View {
        TimelineView(.animation) { context in
            let left = max(0, expires.timeIntervalSince(context.date) / SessionStore.approvalTimeout)
            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: left)
                    .stroke(Palette.needsYou[0], style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
        }
    }
}
