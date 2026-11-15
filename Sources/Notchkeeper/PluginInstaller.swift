import CryptoKit
import Foundation

// `nk plugin install|list|remove|update`: installs plugins from GitHub into ~/.notchkeeper/plugins, turned off.
// curl and tar get plain arguments, no shell, and every name is checked before it reaches a URL or a path.
enum PluginInstaller {
    static let marketplace = ProcessInfo.processInfo.environment["NOTCHKEEPER_MARKETPLACE"]
        ?? "https://thevahidal.github.io/notchkeeper/plugins.json"
    static let sourcesPath = HookInstaller.home + "/.notchkeeper/plugin-sources.json"

    // sha256: for a marketplace plugin, the hash its listing promises; once installed, the hash of what was installed.
    struct Source: Codable {
        var spec: String, repo: String, path: String, commit: String, reviewed: Bool, sha256: String?
        var official: Bool? = nil, author: String? = nil
    }
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static let usage = """
        usage: nk plugin install <id> | <owner>/<repo>[/<folder>][@<ref>] [--as <name>]
               nk plugin list
               nk plugin remove <name>
               nk plugin update [<name>]
        """

    static func main(_ args: [String]) -> Int32 {
        do {
            switch (args.first, args.count) {
            case ("install", 2): try install(args[1], as: nil)
            case ("install", 4) where args[2] == "--as": try install(args[1], as: args[3])
            case ("list", 1): list()
            case ("remove", 2): try remove(args[1])
            case ("update", 1): try sources().keys.sorted().forEach(update)
            case ("update", 2): try update(args[1])
            default:
                print(usage)
                return args.isEmpty ? 0 : 2
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("nk: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    static func install(_ spec: String, as name: String?) throws {
        guard let (source, id) = try resolve(spec, name: name) else { return }
        guard !FileManager.default.fileExists(atPath: Plugins.folder + "/" + id) else {
            throw Failure("\(id) is already installed. Use `nk plugin update \(id)`, or `--as` for another name.")
        }
        try fetch(source, as: id, replacing: false)
    }

    static func update(_ id: String) throws {
        guard let old = sources()[id] else { throw Failure("\(id) wasn't installed with `nk plugin install`") }
        guard let (new, _) = try resolve(old.spec, name: id) else { return }
        guard new.commit != old.commit else { return print("\(id) is up to date.") }
        if new.repo == old.repo { print("Changes: https://github.com/\(new.repo)/compare/\(old.commit)...\(new.commit)") }
        try fetch(new, as: id, replacing: true)
    }

    static func remove(_ id: String) throws {
        let dir = Plugins.folder + "/" + id
        guard validName(id), FileManager.default.fileExists(atPath: dir) else { throw Failure("no plugin named \(id)") }
        try FileManager.default.trashItem(at: URL(fileURLWithPath: dir), resultingItemURL: nil)
        var all = sources()
        all[id] = nil
        save(all)
        print("Moved \(id) to the Trash.")
    }

    static func list() {
        let all = sources()
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: Plugins.folder)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        if names.isEmpty { print("No plugins installed. Built-in plugins are in Settings → Plugins.") }
        for name in names {
            guard let s = all[name] else { print("\(name)  added by hand"); continue }
            print("\(name)  \(s.repo)\(s.path.isEmpty ? "" : "/" + s.path) @ \(s.commit.prefix(7))  \(!s.reviewed ? "unreviewed" : s.official == true ? "official" : "community")")
        }
    }

    // A bare id is a marketplace listing, pinned to its reviewed commit; owner/repo is whatever that ref points to now.
    // nil means there's nothing to download: the plugin comes with the app.
    private static func resolve(_ spec: String, name: String?) throws -> (Source, String)? {
        if let name, !validName(name) { throw Failure("--as takes lowercase letters, digits and dashes") }
        if !spec.contains("/") {
            guard let entry = try listings().first(where: { $0["id"] as? String == spec }) else {
                throw Failure("no plugin \(spec) in the marketplace")
            }
            if entry["builtIn"] as? Bool == true {
                print("\(entry["name"] as? String ?? spec) comes with the app, so it's already installed. Turn it on in Settings → Plugins.")
                return nil
            }
            guard let repo = entry["repo"] as? String, let commit = entry["commit"] as? String, let path = entry["path"] as? String,
                  let hash = entry["sha256"] as? String, hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
                  validRepo(repo), isSha(commit), path.isEmpty || path.split(separator: "/").allSatisfy(safe) else {
                throw Failure("the marketplace listing for \(spec) is invalid")
            }
            return (Source(spec: spec, repo: repo, path: path, commit: commit, reviewed: true, sha256: hash,
                           official: entry["official"] as? Bool == true, author: entry["author"] as? String), name ?? spec)
        }
        let at = spec.lastIndex(of: "@")
        let ref = at.map { String(spec[spec.index(after: $0)...]) } ?? "HEAD"
        let parts = spec[..<(at ?? spec.endIndex)].split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy(safe), ref.range(of: #"^[\w.-]+(/[\w.-]+)*$"#, options: .regularExpression) != nil,
              !ref.contains("..") else {
            throw Failure("use owner/repo, owner/repo/folder or owner/repo@ref")
        }
        let repo = parts[0...1].joined(separator: "/")
        let sha = try String(decoding: curl(["-H", "Accept: application/vnd.github.sha", "https://api.github.com/repos/\(repo)/commits/\(ref)"]), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSha(sha) else { throw Failure("couldn't find \(ref) in github.com/\(repo)") }
        let id = name ?? String(parts.last!).lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard validName(id) else { throw Failure("can't name the plugin from \(parts.last!); pass --as <name>") }
        return (Source(spec: spec, repo: repo, path: parts.dropFirst(2).joined(separator: "/"), commit: sha, reviewed: false, sha256: nil), id)
    }

    // Downloads the commit, checks it with the app's own loader, shows what it is and asks before installing.
    private static func fetch(_ source: Source, as id: String, replacing: Bool) throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("nk-" + UUID().uuidString)
        defer { try? fm.removeItem(at: temp) }
        let unpacked = temp.appendingPathComponent("src"), stage = temp.appendingPathComponent("stage")
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        let tarball = temp.appendingPathComponent("src.tar.gz").path
        _ = try curl(["-o", tarball, "https://codeload.github.com/\(source.repo)/tar.gz/\(source.commit)"])
        try run("/usr/bin/tar", ["-xzf", tarball, "-C", unpacked.path])

        guard let top = try fm.contentsOfDirectory(atPath: unpacked.path).first else { throw Failure("the download was empty") }
        let folder = unpacked.appendingPathComponent(top).appendingPathComponent(source.path)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { throw Failure("no folder \(source.path) in \(source.repo)") }
        let hash = try contentHash(folder.path)
        if let expected = source.sha256, expected != hash {
            throw Failure("the files at \(source.commit.prefix(7)) don't match what the marketplace reviewed. Not installing.")
        }
        try fm.copyItem(at: folder, to: stage.appendingPathComponent(id))
        guard let plugin = Plugins.load(stage.path).first, !plugin.events.isEmpty, plugin.events.isSubset(of: Plugins.events) else {
            throw Failure("not a valid plugin: it needs a plugin.json, a runnable script inside its folder and known events")
        }

        let link = "https://github.com/\(source.repo)/tree/\(source.commit)/\(source.path)"
        print("\(plugin.name) · \(source.repo) @ \(source.commit.prefix(7))")
        if !plugin.description.isEmpty { print(plugin.description) }
        print("Runs on: " + plugin.events.sorted().joined(separator: ", "))
        if !plugin.settings.isEmpty { print("Settings: " + plugin.settings.map(\.title).joined(separator: ", ")) }
        switch (source.reviewed, source.official == true) {
        case (true, true): print("Official Notchkeeper plugin, pinned to a reviewed version.")
        case (true, false):
            print("⚠ Community plugin by \(source.author ?? "a third party"). Reviewed and pinned, but not made or maintained by Notchkeeper.")
            print("  It runs on your Mac with your permissions. Read the code before you install it.")
        default: print("⚠ Not from the marketplace: nobody has reviewed this code. It runs on your Mac with your permissions.")
        }
        print("Code: \(link)")
        print("\(replacing ? "Update" : "Install") \(id)? [y/N] ", terminator: "")
        guard readLine()?.lowercased() == "y" else { throw Failure("cancelled") }

        let dest = Plugins.folder + "/" + id
        try fm.createDirectory(atPath: Plugins.folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if replacing { try fm.trashItem(at: URL(fileURLWithPath: dest), resultingItemURL: nil) }
        try fm.moveItem(at: stage.appendingPathComponent(id), to: URL(fileURLWithPath: dest))
        if !replacing, Plugins.enabled.contains(id) { Plugins.enabled.remove(id) }
        var all = sources()
        all[id] = source
        all[id]?.sha256 = hash
        save(all)
        print(replacing ? "Updated \(id)." : "Installed \(id), turned off. Turn it on in Settings → Plugins.")
    }

    // One line per file, "path\0x-or-dash\0sha256(contents)\n", sorted by path bytes; tools/marketplace.py does the same.
    static func contentHash(_ folder: String) throws -> String {
        let fm = FileManager.default
        let hex = { (digest: SHA256.Digest) in digest.map { String(format: "%02x", $0) }.joined() }
        var lines = Data()
        let paths = (fm.enumerator(atPath: folder)?.allObjects as? [String] ?? []).sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        for path in paths {
            let full = folder + "/" + path
            let attributes = try fm.attributesOfItem(atPath: full)
            if attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw Failure("the plugin contains symlinks, which aren't allowed") }
            guard attributes[.type] as? FileAttributeType == .typeRegular, let data = fm.contents(atPath: full) else { continue }
            let executable = ((attributes[.posixPermissions] as? Int) ?? 0) & 0o111 != 0
            lines.append(Data("\(path)\0\(executable ? "x" : "-")\0\(hex(SHA256.hash(data: data)))\n".utf8))
        }
        return hex(SHA256.hash(data: lines))
    }

    private static func listings() throws -> [[String: Any]] {
        guard let list = try JSONSerialization.jsonObject(with: curl([marketplace])) as? [[String: Any]] else {
            throw Failure("couldn't read the marketplace")
        }
        return list
    }

    private static func sources() -> [String: Source] {
        FileManager.default.contents(atPath: sourcesPath).flatMap { try? JSONDecoder().decode([String: Source].self, from: $0) } ?? [:]
    }

    private static func save(_ all: [String: Source]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(all) else { return }
        FileManager.default.createFile(atPath: sourcesPath, contents: data, attributes: [.posixPermissions: 0o600])
    }

    private static func curl(_ args: [String]) throws -> Data {
        try run("/usr/bin/curl", ["-fsSL", "--proto", "=https,file", "--max-time", "120"] + args)
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) throws -> Data {
        let process = Process(), out = Pipe()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure("\((tool as NSString).lastPathComponent) failed: \(args.last ?? "")") }
        return data
    }

    private static func safe<S: StringProtocol>(_ part: S) -> Bool {
        part != "." && part != ".." && part.range(of: #"^[\w.-]+$"#, options: .regularExpression) != nil
    }
    private static func validRepo(_ repo: String) -> Bool {
        let parts = repo.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy(safe)
    }
    private static func isSha(_ s: String) -> Bool { s.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil }
    private static func validName(_ s: String) -> Bool { s.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil }
}
