import SwiftUI

// The day at a glance: what got done, and who sits at which project's desk.
struct OfficeView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var store: SessionStore
    @StateObject private var scanner = WorkScanner()
    @StateObject private var all = AllWorkScanner()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let entries = ActivityLog.today()
            let projects = projects(entries)
            let selected = projects.first { $0.name == model.desk } ?? projects.first
            GeometryReader { geo in
                // Wide windows get the selected project's details beside the cards.
                if geo.size.width > 980 {
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView { overview(entries, projects, selected).padding(20) }
                            .frame(width: geo.size.width * 0.5)
                        Divider()
                        ScrollView { details(selected, entries).padding(20) }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            overview(entries, projects, selected)
                            details(selected, entries)
                        }
                        .padding(20)
                    }
                }
            }
            .task(id: "\(selected?.name ?? "")|\(context.date)") { scanner.load(selected?.root) }
            .task(id: context.date) { all.load(store.knownFolders) }
        }
    }

    private func overview(_ entries: [ActivityLog.Entry], _ projects: [Project], _ selected: Project?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            today(entries)
            allWorktrees
            section("Projects").padding(.top, 4)
            if projects.isEmpty {
                Text("A project appears when an agent or watch starts work in it.").foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10, alignment: .top)], spacing: 10) {
                ForEach(projects) { project in
                    Button { model.desk = project.name } label: { card(project, entries, selected: project.id == selected?.id) }
                        .buttonStyle(.plain)
                }
            }
            if !ActivityLog.enabled {
                Text("The activity log is off, so today's totals stay empty. Turn it on in Settings.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func details(_ project: Project?, _ entries: [ActivityLog.Entry]) -> some View {
        if let project {
            VStack(alignment: .leading, spacing: 16) {
                needsYou(project)
                whereIsWork(project)
                dayLog(project, entries)
            }
        }
    }

    @ViewBuilder
    private var allWorktrees: some View {
        if !all.repos.isEmpty {
            let removable = all.repos.flatMap { repo in repo.work.worktrees.filter(canRemove).map { (root: repo.root, path: $0.path) } }
            HStack {
                section("All worktrees")
                Spacer()
                if !removable.isEmpty {
                    Button("Remove \(count(removable.count, "safe worktree"))…") { remove(removable) }.controlSize(.small)
                }
            }
            .padding(.top, 4)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(all.repos) { repo in
                    group((repo.root as NSString).lastPathComponent) {
                        ForEach(repo.work.worktrees) { tree in
                            HStack(alignment: .firstTextBaseline) {
                                line((tree.path as NSString).lastPathComponent, state(tree))
                                Spacer()
                                Button("Open") { open(tree.path) }.controlSize(.small)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func state(_ tree: Work.Worktree) -> String {
        var parts: [String] = []
        if !tree.uncommitted.isEmpty { parts.append(count(tree.uncommitted.count, "file") + " not committed") }
        if !tree.ahead.isEmpty { parts.append(count(tree.ahead.count, "commit") + " not merged") }
        if parts.isEmpty { parts.append("Safe to remove") }
        if tree.locked { parts.append("locked by a Claude session") }
        if hasAgent(tree) { parts.append("an agent is in it") }
        return parts.joined(separator: " · ")
    }

    private func hasAgent(_ tree: Work.Worktree) -> Bool {
        store.sessions.contains { !$0.ended && !$0.isItem && ($0.cwd == tree.path || $0.cwd.hasPrefix(tree.path + "/")) }
    }

    private func canRemove(_ tree: Work.Worktree) -> Bool { tree.saved && !tree.locked && !hasAgent(tree) }

    // Plain `git worktree remove`, never --force: git itself refuses one that has changes since the scan. Branches stay.
    private func remove(_ trees: [(root: String, path: String)]) {
        let names = trees.map { ($0.path as NSString).lastPathComponent }
        let alert = NSAlert()
        alert.messageText = "Remove \(count(trees.count, "worktree"))?"
        alert.informativeText = names.joined(separator: "\n") + "\n\nEverything in them is already in the main checkout. Their branches stay."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let folders = store.knownFolders
        DispatchQueue.global(qos: .userInitiated).async { [all] in
            let kept = zip(trees, names).compactMap { tree, name -> String? in
                let (status, out) = ClaudeCLI.run("/usr/bin/git", ["-C", tree.root, "worktree", "remove", tree.path])
                return status == 0 ? nil : name + ": " + (out.split(separator: "\n").first.map(String.init) ?? "git refused")
            }
            DispatchQueue.main.async {
                all.load(folders)
                guard !kept.isEmpty else { return }
                let report = NSAlert()
                report.messageText = "Git kept \(kept.count) of \(trees.count)"
                report.informativeText = kept.joined(separator: "\n")
                report.runModal()
            }
        }
    }

    // In the terminal your agents use, else Finder.
    private func open(_ path: String) {
        if let session = store.sessions.first(where: { $0.term != nil }) { return Jump.open(folder: path, for: session) }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
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

    // A repo and the desks (its own folder and its worktrees) where agents worked today.
    private struct Project: Identifiable {
        var id: String { root ?? name }
        let name: String
        let root: String?
        var desks: [String]
    }

    // In the order they first showed up today, so cards don't jump around.
    private func projects(_ entries: [ActivityLog.Entry]) -> [Project] {
        var desks: [String] = []
        for name in entries.map(\.desk) + store.sessions.map(\.desk) where !name.isEmpty && !desks.contains(name) {
            desks.append(name)
        }
        var roots: [String: String] = [:]
        for desk in desks { roots[desk] = folder(desk).flatMap(Work.projectRoot) }
        // A worktree with no agent left: look for it under the repos already known.
        let known = Set(roots.values)
        for desk in desks where roots[desk] == nil {
            roots[desk] = known.first { FileManager.default.fileExists(atPath: "\($0)/.claude/worktrees/\(desk)") }
        }
        var projects: [Project] = []
        for desk in desks {
            let root = roots[desk]
            if let i = projects.firstIndex(where: { $0.root != nil && $0.root == root }) {
                projects[i].desks.append(desk)
            } else {
                projects.append(Project(name: root.map { ($0 as NSString).lastPathComponent } ?? desk, root: root, desks: [desk]))
            }
        }
        return projects
    }

    @ViewBuilder
    private func card(_ project: Project, _ entries: [ActivityLog.Entry], selected: Bool) -> some View {
        let people = store.sessions.filter { project.desks.contains($0.desk) }
        let here = entries.filter { project.desks.contains($0.desk) }
        let quiet = project.desks.filter { desk in desk != project.name && !people.contains { $0.desk == desk } }.count
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: people.isEmpty ? "folder" : "folder.fill")
                    .foregroundStyle(people.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
                Text(project.name).font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                if let branch = project.root.flatMap(SessionStore.gitBranch) {
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
                    Text(person.title.isEmpty ? who(person) : person.title).lineLimit(1)
                    if person.desk != project.name {
                        Image(systemName: "arrow.triangle.branch").foregroundStyle(.tertiary).help("In worktree \(person.desk)")
                    }
                    Spacer(minLength: 4)
                    Text(status(person)).foregroundStyle(person.state == .needsYou ? .primary : .secondary).fixedSize()
                }
                .font(.caption)
            }
            let turns = here.filter { $0.kind == "yourTurn" && !$0.session.hasPrefix("item:") }.count
            let edits = here.filter { $0.kind == "edit" }.count
            let today = turns + edits > 0 ? "Today: \(count(turns, "turn")) · \(count(edits, "edit"))" : nil
            let rest = quiet > 0 ? count(quiet, "quiet worktree") : nil
            if today != nil || rest != nil {
                Text([today, rest].compactMap { $0 }.joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary)
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
            ?? store.knownFolders.first { ($0 as NSString).lastPathComponent == desk }
    }

    // One plain sentence per thing to act on, riskiest first.
    private struct Nudge: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let text: String
        var since: Date?
        var session: Session?
    }

    private func nudges(_ project: Project) -> [Nudge] {
        let people = store.sessions.filter { project.desks.contains($0.desk) }
        let name = { (s: Session) in s.title.isEmpty ? self.who(s) : s.title }
        var list: [Nudge] = []
        for s in people where s.state == .needsYou {
            list.append(Nudge(id: s.id, icon: "hand.raised.fill", tint: Palette.needsYou[0], text: "\(name(s)) is waiting for you: \(s.question ?? s.detail)", since: s.since, session: s))
        }
        // A finished turn that ends on a question is easy to lose among many agents.
        for s in people where s.state == .yourTurn && !s.ended && (s.question != nil || s.detail.hasSuffix("?")) {
            list.append(Nudge(id: s.id, icon: "questionmark.bubble.fill", tint: Palette.needsYou[1], text: "\(name(s)) asked: “\(s.question ?? s.detail)”", since: s.since, session: s))
        }
        for s in people where s.ended {
            list.append(Nudge(id: s.id, icon: "exclamationmark.triangle.fill", tint: Palette.danger, text: "\(name(s)) ended with unsaved work: \(s.unsaved ?? "")", since: s.since, session: s))
        }
        guard let work = scanner.work, scanner.folder == project.root else { return list }
        let busy = Set(people.filter { $0.state == .working }.map(\.desk))
        for tree in work.worktrees where !tree.saved {
            let folder = (tree.path as NSString).lastPathComponent
            guard !busy.contains(folder) else { continue }
            let label = tree.agent ?? folder
            if !tree.ahead.isEmpty {
                let what = tree.ahead.count == 1 ? "“\(tree.ahead[0].subject)” isn't" : "\(tree.ahead.count) commits aren't"
                list.append(Nudge(id: tree.path + "/ahead", icon: "arrow.triangle.merge", tint: Palette.plan, text: "\(label): \(what) in \(work.branch) yet."))
            }
            if !tree.uncommitted.isEmpty {
                list.append(Nudge(id: tree.path + "/dirty", icon: "doc.badge.ellipsis", tint: Palette.plan,
                                  text: "\(label) left \(count(tree.uncommitted.count, "file")) uncommitted, and no agent is working there."))
            }
        }
        for group in work.uncommitted {
            let files = count(group.files.count, "file")
            list.append(Nudge(id: "dirty/" + group.who, icon: "doc.badge.ellipsis", tint: Palette.plan, text: group.who.isEmpty
                ? "\(files) in \(work.branch) \(group.files.count == 1 ? "is" : "are") uncommitted, and no agent edited them today."
                : "\(group.who) left \(files) uncommitted in \(work.branch)."))
        }
        if !work.unpushed.isEmpty {
            list.append(Nudge(id: "unpushed", icon: "icloud.and.arrow.up", tint: Palette.plan, text: "\(count(work.unpushed.count, "commit")) on \(work.branch) \(work.unpushed.count == 1 ? "isn't" : "aren't") pushed."))
        }
        if !work.missing.isEmpty {
            list.append(Nudge(id: "missing", icon: "arrow.triangle.pull", tint: Palette.plan, text: "\(count(work.missing.count, "commit")) on other branches \(work.missing.count == 1 ? "isn't" : "aren't") in \(work.branch)."))
        }
        let saved = work.worktrees.filter(\.saved).count
        if saved > 0 {
            list.append(Nudge(id: "saved", icon: "archivebox", tint: .secondary, text: "\(count(saved, "worktree")) \(saved == 1 ? "is" : "are") fully merged. Archive their sessions to clean up."))
        }
        return list
    }

    private func needsYou(_ project: Project) -> some View {
        let list = nudges(project)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            section("Needs you")
            if list.isEmpty {
                Label("Nothing right now. Everything here is saved.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            }
            ForEach(list) { nudge in
                if let session = nudge.session {
                    Button { store.jump(to: session) } label: { nudgeRow(nudge, link: true) }
                        .buttonStyle(.plain)
                        .help(session.ended ? "Open its folder" : "Go to this agent")
                } else {
                    nudgeRow(nudge, link: false)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: shape)
    }

    private func nudgeRow(_ nudge: Nudge, link: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: nudge.icon).foregroundStyle(nudge.tint).frame(width: 18)
            Text(nudge.text).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            if let since = nudge.since { Text(Elapsed.short(Date().timeIntervalSince(since))).foregroundStyle(.tertiary).monospacedDigit() }
            if link { Image(systemName: "arrow.up.forward").foregroundStyle(.secondary) }
        }
        .font(.callout)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func whereIsWork(_ project: Project) -> some View {
        if let work = scanner.work, scanner.folder == project.root {
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

    private func dayLog(_ project: Project, _ entries: [ActivityLog.Entry]) -> some View {
        let rows = rows(entries.filter { project.desks.contains($0.desk) }, main: project.name)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            section("\(project.name) today").padding(.bottom, 10)
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
    // Worktree activity names its worktree, so a project's log reads as one story.
    private func rows(_ entries: [ActivityLog.Entry], main: String) -> [Row] {
        var rows: [Row] = []
        var previous: [String: String] = [:]
        for entry in entries {
            defer { previous[entry.session] = entry.kind }
            let isItem = entry.session.hasPrefix("item:")
            let agent = (Agent(rawValue: entry.agent) ?? .claude).title + (entry.desk == main ? "" : " in \(entry.desk)")
            let who = isItem ? entry.title : agent
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
