import Foundation

// Where a folder's work stands in git, named rather than counted. Read-only and local: it never fetches.
struct Work: Equatable {
    struct Commit: Equatable, Identifiable {
        let id: String
        let subject: String
        var places: [String] = []
    }
    // Files one agent left uncommitted; who is "" for files no agent edited today.
    struct Group: Equatable {
        let who: String
        var files: [String]
    }
    struct Worktree: Equatable, Identifiable {
        var id: String { path }
        let path: String
        var agent: String?
        var uncommitted: [String] = []
        // Commits it has that the main checkout doesn't.
        var ahead: [Commit] = []
        // Claude desktop locks a worktree while its session exists.
        var locked = false
        var saved: Bool { uncommitted.isEmpty && ahead.isEmpty }
    }
    var branch = ""
    var uncommitted: [Group] = []
    var unpushed: [Commit] = []
    // Commits on other branches (the remote's copy, branches not in a worktree) this branch doesn't have.
    var missing: [Commit] = []
    // Main checkout only.
    var worktrees: [Worktree] = []
    var fetched: Date?

    static func scan(_ folder: String, log: [ActivityLog.Entry]) -> Work? {
        guard SessionStore.gitBranch(folder) != nil else { return nil }
        // Skips git's optional locks so it never gets in the way of an agent's own git.
        func git(_ args: [String]) -> String? {
            let (status, out) = ClaudeCLI.run("/usr/bin/git", ["--no-optional-locks", "-C", folder] + args)
            return status == 0 ? out : nil
        }
        func commits(_ args: [String]) -> [Commit] {
            (git(["log", "--no-merges", "--format=%H%x09%s", "-n", "30"] + args) ?? "").split(separator: "\n").compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                return parts.count == 2 ? Commit(id: parts[0], subject: parts[1]) : nil
            }
        }
        func path(_ args: [String]) -> String? { git(["rev-parse", "--path-format=absolute"] + args)?.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let status = git(["status", "--porcelain", "-z"]), let root = path(["--show-toplevel"]) else { return nil }
        var work = Work(branch: SessionStore.gitBranch(folder) ?? "")
        work.uncommitted = attribute(changedFiles(status), root: root, log: log)

        let remotes = !(git(["remote"]) ?? "").isEmpty
        if remotes { work.unpushed = commits(["HEAD", "--not", "--remotes"]) }

        // Only the main checkout gathers work from the others; a worktree being behind its base is expected.
        let common = path(["--git-common-dir"])
        let isMain = common != nil && common == path(["--git-dir"])
        if isMain { work.worktrees = worktrees(git(["worktree", "list", "--porcelain"]) ?? "", root: root, log: log, commits: commits) }
        let inWorktrees = Set(work.worktrees.compactMap { SessionStore.gitBranch($0.path) })
        var refs = isMain ? (git(["for-each-ref", "--format=%(refname:short)", "refs/heads"]) ?? "").split(separator: "\n").map(String.init) : []
        if let upstream = git(["rev-parse", "--abbrev-ref", "@{u}"])?.trimmingCharacters(in: .whitespacesAndNewlines) { refs.append(upstream) }
        var missing: [Commit] = []
        for ref in refs where ref != work.branch && !inWorktrees.contains(ref) {
            // Commits already here under another hash (cherry-picked, rebased) don't count.
            for commit in commits(["--cherry-pick", "--right-only", "HEAD...\(ref)"]) {
                if let i = missing.firstIndex(where: { $0.id == commit.id }) { missing[i].places.append(ref) } else { missing.append(Commit(id: commit.id, subject: commit.subject, places: [ref])) }
            }
        }
        work.missing = missing
        if let common {
            work.fetched = (try? FileManager.default.attributesOfItem(atPath: common + "/FETCH_HEAD"))?[.modificationDate] as? Date
        }
        return work
    }

    // Each linked worktree: who worked there, and what in it isn't in the main checkout yet.
    private static func worktrees(_ list: String, root: String, log: [ActivityLog.Entry], commits: ([String]) -> [Commit]) -> [Worktree] {
        list.components(separatedBy: "\n\n").compactMap { block -> Worktree? in
            let lines = block.split(separator: "\n").map(String.init)
            guard let path = lines.first(where: { $0.hasPrefix("worktree ") })?.dropFirst(9).description, path != root,
                  !lines.contains(where: { $0.hasPrefix("prunable") }),
                  let head = lines.first(where: { $0.hasPrefix("HEAD ") })?.dropFirst(5).description else { return nil }
            var tree = Worktree(path: path, locked: lines.contains { $0.hasPrefix("locked") })
            let desk = (path as NSString).lastPathComponent
            tree.agent = log.last { $0.desk == desk && !$0.title.isEmpty }?.title
            let (status, out) = ClaudeCLI.run("/usr/bin/git", ["--no-optional-locks", "-C", path, "status", "--porcelain", "-z"])
            if status == 0 { tree.uncommitted = changedFiles(out) }
            tree.ahead = commits(["--cherry-pick", "--right-only", "HEAD...\(head)"])
            return tree
        }
        // Ones that still hold work first.
        .sorted { ($0.saved ? 1 : 0, $0.path) < ($1.saved ? 1 : 0, $1.path) }
    }

    // The main checkout a folder belongs to, read from .git without running git; nil outside a repo.
    static func projectRoot(_ path: String) -> String? {
        var dir = URL(fileURLWithPath: path)
        while dir.path != "/" {
            let git = dir.appendingPathComponent(".git")
            if let link = try? String(contentsOf: git, encoding: .utf8), link.hasPrefix("gitdir: ") {
                let target = link.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines)
                return target.range(of: "/.git/worktrees/").map { String(target[..<$0.lowerBound]) } ?? dir.path
            }
            if FileManager.default.fileExists(atPath: git.path) { return dir.path }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    // `status --porcelain -z`: "XY path", and renames carry the old path as an extra field.
    static func changedFiles(_ status: String) -> [String] {
        var files: [String] = []
        var fields = status.split(separator: "\0", omittingEmptySubsequences: true).makeIterator()
        while let field = fields.next() {
            guard field.count > 3 else { continue }
            files.append(String(field.dropFirst(3)))
            if field.first == "R" || field.first == "C" { _ = fields.next() }
        }
        return files
    }

    // By full path, from today's log: the session that last edited each file.
    static func attribute(_ files: [String], root: String, log: [ActivityLog.Entry]) -> [Group] {
        func real(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().path }
        var titles: [String: String] = [:]
        for entry in log where !entry.title.isEmpty { titles[entry.session] = entry.title }
        var lastEditor: [String: String] = [:]
        for entry in log where entry.kind == "edit" && entry.path.hasPrefix("/") { lastEditor[real(entry.path)] = entry.session }
        var groups: [Group] = []
        for file in files {
            let who = lastEditor[real(root + "/" + file)].map { titles[$0] ?? "An agent" } ?? ""
            if let i = groups.firstIndex(where: { $0.who == who }) { groups[i].files.append(file) } else { groups.append(Group(who: who, files: [file])) }
        }
        // Named agents first, the most files first; unclaimed files last.
        return groups.sorted { ($0.who.isEmpty ? 1 : 0, -$0.files.count) < ($1.who.isEmpty ? 1 : 0, -$1.files.count) }
    }
}

final class WorkScanner: ObservableObject {
    @Published private(set) var work: Work?
    private(set) var folder: String?

    func load(_ folder: String?) {
        if folder != self.folder { work = nil }
        self.folder = folder
        guard let folder else { return }
        let log = ActivityLog.today()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let work = Work.scan(folder, log: log)
            DispatchQueue.main.async {
                guard self?.folder == folder, self?.work != work else { return }
                self?.work = work
            }
        }
    }
}
