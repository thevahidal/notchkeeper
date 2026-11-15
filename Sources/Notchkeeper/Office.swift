import SwiftUI

// The day at a glance: what got done, and who sits at which project's desk.
struct OfficeView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var store: SessionStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let entries = ActivityLog.today()
            let desks = desks(entries)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    today(entries)
                    Text("Desks").font(.caption).foregroundStyle(.secondary)
                    if desks.isEmpty {
                        Text("A desk appears when an agent or watch starts work in a project.").foregroundStyle(.secondary)
                    }
                    let selected = desks.contains(model.desk ?? "") ? model.desk : desks.first
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10, alignment: .top)], spacing: 10) {
                        ForEach(desks, id: \.self) { name in
                            Button { model.desk = name } label: { desk(name, entries, selected: name == selected) }
                                .buttonStyle(.plain)
                        }
                    }
                    if let selected { dayLog(selected, entries) }
                    if !ActivityLog.enabled {
                        Text("The activity log is off, so today's totals stay empty. Turn it on in Settings.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
        }
    }

    private func today(_ entries: [ActivityLog.Entry]) -> some View {
        let agents = entries.filter { !$0.session.hasPrefix("item:") }
        let approvals = entries.filter { $0.kind == "approval" }
        let denied = approvals.filter { $0.detail.hasPrefix("deny") }.count
        let files = Set(entries.filter { $0.kind == "edit" }.map { $0.desk + "/" + $0.detail }).count
        return HStack(spacing: 10) {
            metric("\(agents.filter { $0.kind == "yourTurn" }.count)", "turns finished")
            metric("\(approvals.count)", denied > 0 ? "approvals, \(denied) denied" : "approvals")
            metric("\(files)", "files edited")
            metric(waited(agents) < 60 ? "0m" : Elapsed.short(waited(agents)), "agents waited on you")
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.medium)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(.headline).lineLimit(1)
                Spacer()
                if let branch = people.compactMap(\.branch).first {
                    Text(branch).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), lineWidth: selected ? 2 : 1))
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
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(name) today").font(.headline).padding(.bottom, 6)
            if rows.isEmpty {
                Text("Nothing logged here today.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(rows.reversed().prefix(100)) { row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(row.time.formatted(date: .omitted, time: .shortened)).monospacedDigit().foregroundStyle(.tertiary).frame(width: 64, alignment: .leading)
                    Text(row.text).foregroundStyle(row.denied ? Color.red : Color.primary).textSelection(.enabled)
                }
                .font(.callout)
                .padding(.vertical, 4)
                Divider()
            }
        }
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
