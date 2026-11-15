import Foundation

// What happened at each desk today, for the Office: state changes, edits, approvals. Local only, ~/.notchkeeper/activity.log.
enum ActivityLog {
    static let path = (ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()) + "/.notchkeeper/activity.log"

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "activityLog") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "activityLog") }
    }

    static func record(_ kind: String, _ session: Session) {
        record(kind, desk: session.desk, session: session.id, agent: session.agent ?? "claude", title: session.title, detail: session.detail)
    }

    static func record(_ kind: String, desk: String, session: String, agent: String? = nil, title: String = "", detail: String) {
        guard enabled else { return }
        var entry: [String: Any] = ["time": ISO8601DateFormatter().string(from: Date()), "kind": kind, "desk": desk,
                                    "session": session, "detail": String(detail.prefix(200))]
        if let agent { entry["agent"] = agent }
        if !title.isEmpty { entry["title"] = String(title.prefix(120)) }
        AuditLog.append(entry, to: path)
    }

    struct Entry {
        let time: Date
        let kind, desk, session, agent, title, detail: String
    }

    private static var cache: (modified: Date, entries: [Entry])?

    // Today's lines, oldest first. Re-read only when the file changes.
    static func today() -> [Entry] {
        let start = Calendar.current.startOfDay(for: Date())
        let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date ?? .distantPast
        if cache?.modified != modified {
            let iso = ISO8601DateFormatter()
            let text = [path + ".1", path].compactMap { try? String(contentsOfFile: $0, encoding: .utf8) }.joined(separator: "\n")
            let entries = text.split(separator: "\n").compactMap { line -> Entry? in
                guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let time = (o["time"] as? String).flatMap(iso.date), time >= start else { return nil }
                return Entry(time: time, kind: o["kind"] as? String ?? "", desk: o["desk"] as? String ?? "",
                             session: o["session"] as? String ?? "", agent: o["agent"] as? String ?? "",
                             title: o["title"] as? String ?? "", detail: o["detail"] as? String ?? "")
            }
            cache = (modified, entries)
        }
        return cache!.entries.filter { $0.time >= start }
    }
}
