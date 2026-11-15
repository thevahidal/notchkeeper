import SwiftUI

struct NotchView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var state: NotchState

    var body: some View {
        let approval = store.approvals.first
        let card = approval != nil || store.replyTo != nil || store.offerConnect
        let size = state.size(for: store.sorted, card: card)
        let radius: CGFloat = state.expanded || card ? 22 : 10
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius)

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(.black)
                if let approval {
                    ApprovalCard(approval: approval, notchHeight: state.notch.height) { store.answer(approval, $0) }
                        .transition(.opacity.animation(.easeOut(duration: 0.2).delay(0.12)))
                } else if store.offerConnect {
                    ConnectCard(store: store, notchHeight: state.notch.height)
                        .transition(.opacity.animation(.easeOut(duration: 0.2).delay(0.12)))
                } else if let session = store.replyTo {
                    ReplyCard(store: store, session: session, notchHeight: state.notch.height)
                        .transition(.opacity.animation(.easeOut(duration: 0.2).delay(0.12)))
                } else if state.expanded {
                    expanded.transition(.opacity.animation(.easeOut(duration: 0.2).delay(0.12)))
                } else {
                    collapsed.transition(.opacity.animation(.easeOut(duration: 0.12)))
                }
                if store.mood != .idle { glow(width: size.width) }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: state.expanded)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: store.sessions.map(\.id))
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: approval?.id)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: store.replyTo?.id)
    }

    private var collapsed: some View {
        let sessions = store.sorted
        let ear = state.earWidth(sessions.count)
        // Seen sessions are parked: they don't show up in the counts.
        let counts = [SessionState.needsYou, .yourTurn, .working]
            .map { s in (s, sessions.filter { $0.state == s && !$0.seen }.count) }
            .filter { $0.1 > 0 }

        return HStack(spacing: 0) {
            HStack(spacing: 5) {
                if sessions.count > state.maxDots {
                    ForEach(counts, id: \.0) { s, n in
                        HStack(spacing: 2) {
                            Orb(state: s)
                            Text("\(n)").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Palette.orb(s))
                        }
                    }
                } else {
                    ForEach(sessions) { Orb(state: $0.state, seen: $0.seen).transition(.scale.combined(with: .opacity)) }
                }
            }
            .frame(width: ear)
            Spacer()
            Text(waitingCount > 0 ? "\(waitingCount)" : "")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(store.mood == .needsYou ? Palette.needsYou[0] : Palette.yourTurn[0])
                .frame(width: ear)
        }
        .frame(height: state.notch.height)
    }

    private var expanded: some View {
        let sessions = store.sorted

        return VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: state.notch.height + 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sessions) { row($0) }
                }
            }
            .frame(height: state.listHeight(sessions))
        }
        .padding(.horizontal, 20)
    }

    private func row(_ session: Session) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Orb(state: session.state, seen: session.seen)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 6) {
                    AppIcon(session: session)
                    Text(session.title.isEmpty ? session.repo : session.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !session.subagents.isEmpty {
                        Text("⑂ \(session.subagents.count)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.working[1])
                    }
                    Spacer(minLength: 8)
                    if let mode = session.mode { ModeBadge(mode: mode) }
                    if !session.title.isEmpty {
                        Text(session.repo)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                HStack(spacing: 8) {
                    detail(session)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(session.question == nil ? .middle : .tail)
                    Spacer(minLength: 0)
                    Text([session.model, session.effort].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                        .fixedSize()
                }
                ForEach(session.subagents) { agent in
                    Text("↳ \(agent.type)").foregroundColor(Palette.working[1])
                        + Text([agent.description, agent.detail].filter { !$0.isEmpty }.map { " · " + $0 }.joined())
                        .foregroundColor(.white.opacity(0.45))
                }
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(height: state.subagentHeight - 3, alignment: .leading)
            }
            if session.state != .working && Jump.canReply(session) {
                Button { store.replyTo = session } label: {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 26, height: 26)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: state.height(of: session), maxHeight: state.height(of: session), alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { store.jump(to: session) }
    }

    private func detail(_ session: Session) -> Text {
        if let question = session.question { return Text(question).foregroundColor(.white.opacity(0.85)) }
        guard session.state == .yourTurn else { return Text(session.detail) }
        return Text(session.detail + " · ") + Text(session.lastSeen, style: .relative)
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

    private var waitingCount: Int {
        store.sessions.filter { $0.state != .working && !$0.seen }.count
    }
}

enum Palette {
    static let working = [Color(red: 0.50, green: 0.47, blue: 0.87), Color(red: 0.36, green: 0.79, blue: 0.65)]
    static let needsYou = [Color(red: 0.94, green: 0.62, blue: 0.15), Color(red: 0.94, green: 0.60, blue: 0.48)]
    static let yourTurn = [Color(red: 0.59, green: 0.77, blue: 0.35), Color(red: 0.36, green: 0.79, blue: 0.65)]

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
        case .working: Color(red: 0.69, green: 0.66, blue: 0.93)
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

    var body: some View {
        let color = Palette.orb(state).opacity(seen ? 0.4 : 1)
        let rate = seen ? 0 : state == .needsYou ? 4.0 : state == .yourTurn ? 1.6 : 0
        TimelineView(.animation(paused: rate == 0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.9), radius: 3)
                .opacity(rate > 0 ? 0.65 + 0.35 * sin(t * rate) : 1)
        }
    }
}

struct ApprovalCard: View {
    let approval: Approval
    let notchHeight: CGFloat
    let onAnswer: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: notchHeight - 6)
            HStack(spacing: 8) {
                Orb(state: .needsYou)
                Text(approval.repo)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Text("wants to use \(approval.tool)")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Countdown(expires: approval.expires)
            }
            Text(approval.target)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 8) {
                CardButton(title: "Allow  ⌥Y", fill: Palette.yourTurn[0], text: .black) { onAnswer("allow") }
                CardButton(title: "Deny  ⌥N", fill: .white.opacity(0.14), text: .white) { onAnswer("deny") }
                Spacer()
                CardButton(title: "Use terminal", fill: .clear, text: .white.opacity(0.6)) { onAnswer("terminal") }
            }
        }
        .padding(.horizontal, 18)
    }
}

struct CardButton: View {
    let title: String
    let fill: Color
    let text: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(text)
                .padding(.horizontal, 14)
                .frame(height: 26)
                .background(fill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// Claude's icon; CLI sessions get a badge of their terminal app (or a terminal symbol).
struct AppIcon: View {
    let session: Session

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Self.icon("com.anthropic.claudefordesktop").resizable().frame(width: 15, height: 15)
            if session.tty != nil {
                (Jump.appId(session).map(Self.icon) ?? Image(systemName: "terminal"))
                    .resizable()
                    .frame(width: 9, height: 9)
                    .offset(x: 4, y: 3)
            }
        }
    }

    private static func icon(_ bundleId: String) -> Image {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        return Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage())
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
            Text("Connect Ping to Claude Code?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(store.connectError ?? "Adds Ping's hooks to ~/.claude/settings.json (a backup is kept). Events stay on this Mac.")
                .font(.system(size: 12))
                .foregroundStyle(store.connectError == nil ? .white.opacity(0.6) : Palette.needsYou[0])
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                CardButton(title: "Connect", fill: Palette.yourTurn[0], text: .black) { store.connect() }
                CardButton(title: "Not now", fill: .white.opacity(0.14), text: .white) { store.declineConnect() }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 18)
    }
}

struct ReplyCard: View {
    @ObservedObject var store: SessionStore
    let session: Session
    let notchHeight: CGFloat
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: notchHeight - 6)
            HStack(spacing: 8) {
                Orb(state: session.state)
                Text(session.title.isEmpty ? session.repo : session.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Text("↩ send   esc cancel")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Text(session.detail)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
            TextField("Reply…", text: $store.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(8)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
            Circle()
                .trim(from: 0, to: left)
                .stroke(Palette.needsYou[0], style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 14, height: 14)
        }
    }
}
