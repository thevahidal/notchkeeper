import SwiftUI

// The day at a glance: what got done, and who sits at which project's desk.
struct OfficeView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var store: SessionStore
    @StateObject private var scanner = WorkScanner()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let entries = ActivityLog.today()
            let desks = desks(entries)
            let selected = desks.contains(model.desk ?? "") ? model.desk : desks.first
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    today(entries)
                    section("Desks").padding(.top, 4)
                    if desks.isEmpty {
                        Text("A desk appears when an agent or watch starts work in a project.").foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10, alignment: .top)], spacing: 10) {
                        ForEach(desks, id: \.self) { name in
                            Button { model.desk = name } label: { desk(name, entries, selected: name == selected) }
                                .buttonStyle(.plain)
                        }
                    }
                    if let selected {
                        whereIsWork(selected)
                        dayLog(selected, entries)
                    }
                    if !ActivityLog.enabled {
                        Text("The activity log is off, so today's totals stay empty. Turn it on in Settings.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .task(id: "\(selected ?? "")|\(context.date)") { scanner.load(selected.flatMap(folder)) }
            }
        }
    }

    private func today(_ entries: [ActivityLog.Entry]) -> some View {
        let agents = entries.filter { !$0.session.hasPrefix("item:") }
        let approvals = entries.filter { $0.kind == "approval" }
        let denied = approvals.filter { $0.detail.hasPrefix("deny") }.count
        let files = Set(entries.filter { $0.kind == "edit" }.map { $0.desk + "/" + $0.detail }).count
        return HStack(spacing: 10) {
            metric("\(agents.filter { $0.kind == "yourTurn" }.count)", "turns finished", "checkmark.circle.fill", Palette.yourTurn[0])
            metric("\(approvals.count)", denied > 0 ? "approvals, \(denied) denied" : "approvals", "hand.raised.fill", Palette.needsYou[0])
            metric("\(files)", "files edited", "doc.text.fill", Palette.plan)
            metric(waited(agents) < 60 ? "0m" : Elapsed.short(waited(agents)), "waited on you", "hourglass", Palette.needsYou[1])
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func metric(_ value: String, _ label: String, _ icon: String, _ tint: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.18), in: Circle())
            Spacer(minLength: 0)
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [tint.opacity(0.14), tint.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing), in: shape)
        .overlay(shape.strokeBorder(tint.opacity(0.22), lineWidth: 1))
    }

    // From each "needs you" to whatever came next for that session; still counting if it waits now.
    private func waited(_ entries: [ActivityLog.Entry]) -> TimeInterval {
        var total: TimeInterval = 0
        var since: [String: Date] = [:]
        for entry in entries {
            if let start = since.removeValue(forKey: entry.session) { total += entry.time.timeIntervalSince(start) }
            if entry.kind == "needsYou" { since[entry.session] = entry.time }
        }
        for (id, start) in since where store.sessions.contains(where: { $0.id == id && $0.state == .needsYou }) {
            total += Date().timeIntervalSince(start)
        }
        return total
    }

    // In the order they first showed up today, so cards don't jump around.
    private func desks(_ entries: [ActivityLog.Entry]) -> [String] {
        var names: [String] = []
        for name in entries.map(\.desk) + store.sessions.map(\.desk) where !name.isEmpty && !names.contains(name) {
            names.append(name)
        }
        return names
    }

    @ViewBuilder
    private func desk(_ name: String, _ entries: [ActivityLog.Entry], selected: Bool) -> some View {
        let people = store.sessions.filter { $0.desk == name }
        let here = entries.filter { $0.desk == name }
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: people.isEmpty ? "folder" : "folder.fill")
                    .foregroundStyle(people.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
                Text(name).font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                if let branch = people.compactMap(\.branch).first {
                    Label(branch, systemImage: "arrow.triangle.branch").font(.caption2).lineLimit(1)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.quaternary.opacity(0.6), in: Capsule())
                }
            }
            if people.isEmpty {
                Text(here.last.map { "Empty since \($0.time.formatted(date: .omitted, time: .shortened))" } ?? "Empty")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(people) { person in
                HStack(spacing: 6) {
                    Circle().fill(Palette.orb(person.state)).frame(width: 7, height: 7)
                    Text(who(person)).lineLimit(1)
                    Text(status(person)).foregroundStyle(person.state == .needsYou ? .primary : .secondary).fixedSize()
                }
                .font(.caption)
            }
            let turns = here.filter { $0.kind == "yourTurn" && !$0.session.hasPrefix("item:") }.count
            let edits = here.filter { $0.kind == "edit" }.count
            if turns + edits > 0 {
                Text("Today: \(count(turns, "turn")) · \(count(edits, "edit"))").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(selected ? AnyShapeStyle(Color.accentColor.opacity(0.10)) : AnyShapeStyle(.quaternary.opacity(0.35)), in: shape)
        .overlay(shape.strokeBorder(selected ? AnyShapeStyle(Color.accentColor.opacity(0.8)) : AnyShapeStyle(.quaternary), lineWidth: selected ? 1.5 : 1))
        .contentShape(shape)
    }

    // A live agent's folder, else one agents ran in lately.
    private func folder(_ desk: String) -> String? {
        store.sessions.first { $0.desk == desk && !$0.cwd.isEmpty }?.cwd
            ?? store.recentFolders.first { ($0 as NSString).lastPathComponent == desk }
    }

    @ViewBuilder
    private func whereIsWork(_ desk: String) -> some View {
        if let work = scanner.work, scanner.folder == folder(desk) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Where's my work").font(.headline)
                    Text(work.branch).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(work.fetched.map { "Remote as of \($0.formatted(.relative(presentation: .named)))" } ?? "Never fetched")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                if work.uncommitted.isEmpty && work.unpushed.isEmpty && work.missing.isEmpty && work.worktrees.allSatisfy(\.saved) {
                    Label("All committed and pushed, and nothing on other branches is missing here.", systemImage: "checkmark.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if !work.uncommitted.isEmpty {
                    group("Not committed") {
                        ForEach(work.uncommitted, id: \.who) { g in
                            line(g.who.isEmpty ? "Not from an agent today" : g.who, Self.files(g.files.map { ($0 as NSString).lastPathComponent }))
                        }
                    }
                }
                if !work.unpushed.isEmpty {
                    group("Not pushed") { ForEach(work.unpushed) { line($0.subject, nil) } }
                }
                if !work.missing.isEmpty {
                    group("On other branches, missing here") { ForEach(work.missing) { line($0.subject, $0.places.joined(separator: ", ")) } }
                }
                let holding = work.worktrees.filter { !$0.saved }
                if !holding.isEmpty {
                    group("Worktrees with work not here") {
                        ForEach(holding) { tree in
                            VStack(alignment: .leading, spacing: 2) {
                                line((tree.path as NSString).lastPathComponent, tree.agent)
                                Group {
                                    if !tree.uncommitted.isEmpty {
                                        Text("Not committed: " + Self.files(tree.uncommitted.map { ($0 as NSString).lastPathComponent }))
                                    }
                                    ForEach(tree.ahead) { Text("Not merged: " + $0.subject) }
                                }
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(.leading, 12)
                            }
                        }
                    }
                }
                let saved = work.worktrees.filter(\.saved)
                if !saved.isEmpty {
                    group("Safe to remove") {
                        Text(saved.map { ($0.path as NSString).lastPathComponent }.joined(separator: ", "))
                            .font(.callout).textSelection(.enabled)
                        if saved.contains(where: \.locked) {
                            Text("Everything in these is merged here. Locked ones belong to a Claude session; archive it to remove the worktree.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func line(_ title: String, _ detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).lineLimit(1)
            if let detail { Text(detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
        }
        .font(.callout)
        .textSelection(.enabled)
    }

    private struct Row: Identifiable {
        let id: Int
        let time: Date
        var text: String
        var files: [String] = []
        var denied = false
    }

    private func dayLog(_ name: String, _ entries: [ActivityLog.Entry]) -> some View {
        let rows = rows(entries.filter { $0.desk == name })
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            section("\(name) today").padding(.bottom, 10)
            if rows.isEmpty {
                Text("Nothing logged here today.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(rows.reversed().prefix(100).enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().padding(.leading, 74) }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(row.time.formatted(date: .omitted, time: .shortened)).monospacedDigit().foregroundStyle(.tertiary).frame(width: 64, alignment: .leading)
                    Text(row.text).foregroundStyle(row.denied ? Palette.danger : Color.primary).textSelection(.enabled)
                }
                .font(.callout)
                .padding(.vertical, 6)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.25), in: shape)
        .overlay(shape.strokeBorder(.quaternary, lineWidth: 1))
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
    }

    // One readable line per event. Edits in a row merge, and "working again" after you answer is left out.
    private func rows(_ entries: [ActivityLog.Entry]) -> [Row] {
        var rows: [Row] = []
        var previous: [String: String] = [:]
        for entry in entries {
            defer { previous[entry.session] = entry.kind }
            let isItem = entry.session.hasPrefix("item:")
            let who = isItem ? entry.title : (Agent(rawValue: entry.agent) ?? .claude).title
            var text: String
            switch entry.kind {
            case "edit":
                if var last = rows.last, last.files.count > 0, previous[entry.session] == "edit" {
                    if !last.files.contains(entry.detail) { last.files.append(entry.detail) }
                    last.text = "\(who) edited " + Self.files(last.files)
                    rows[rows.count - 1] = last
                    continue
                }
                rows.append(Row(id: rows.count, time: entry.time, text: "\(who) edited \(entry.detail)", files: [entry.detail]))
                continue
            case "working":
                guard !["needsYou", "approval", "working", "edit"].contains(previous[entry.session] ?? "") else { continue }
                text = isItem ? "Started \(entry.title)" : entry.title.isEmpty ? "\(who) started working" : "\(who) started: \(entry.title)"
            case "needsYou": text = isItem ? "\(who): \(entry.detail)" : "\(who) asked: \(entry.detail)"
            case "yourTurn":
                text = isItem ? "\(who): \(entry.detail)" : entry.detail == "Your turn" ? "\(who) finished a turn" : "\(who) finished: “\(entry.detail)”"
            case "approval": text = Self.approval(entry.detail)
            case "end": text = "\(who) session ended"
            default: continue
            }
            rows.append(Row(id: rows.count, time: entry.time, text: text, denied: entry.kind == "approval" && entry.detail.hasPrefix("deny")))
        }
        return rows
    }

    private static func files(_ files: [String]) -> String {
        files.count <= 3 ? files.joined(separator: ", ") : files.prefix(3).joined(separator: ", ") + " +\(files.count - 3)"
    }

    // "allow: Bash ./build.sh" → "You allowed Bash ./build.sh"
    private static func approval(_ detail: String) -> String {
        let parts = detail.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let what = parts.count > 1 ? parts[1] : ""
        switch parts.first {
        case "allow": return "You allowed \(what)"
        case "session": return "You allowed \(what) for the session"
        case "deny", "deny-message": return "You denied \(what)"
        case "timeout": return "No answer in time: \(what)"
        case "terminal": return "You answered in the terminal: \(what)"
        default: return detail
        }
    }

    private func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    private func who(_ session: Session) -> String {
        if session.isItem { return session.title }
        return (Agent(rawValue: session.agent ?? "claude") ?? .claude).title
    }

    private func status(_ session: Session) -> String {
        let time = Elapsed.short(Date().timeIntervalSince(session.since))
        switch session.state {
        case .needsYou: return "· waiting \(time)"
        case .yourTurn: return time == "now" ? "· just done" : "· done \(time) ago"
        case .working: return "· working"
        }
    }
}
