import Foundation

// Every answer given from the notch, one JSON line each, in ~/.ping/approvals.log. Local only.
enum AuditLog {
    private static let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    static let path = home + "/.ping/approvals.log"

    static func record(_ approval: Approval, _ decision: String) {
        let entry: [String: Any] = [
            "time": ISO8601DateFormatter().string(from: Date()),
            "decision": decision,
            "repo": approval.repo,
            "tool": approval.tool,
            "target": approval.target,
            "risk": ["low", "medium", "high"][approval.risk.level.rawValue],
            "reasons": approval.risk.reasons,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        let fm = FileManager.default
        // Keep it small: past 1 MB, the old log moves aside and a new one starts.
        if let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? Int, size > 1_000_000 {
            try? fm.removeItem(atPath: path + ".1")
            try? fm.moveItem(atPath: path, toPath: path + ".1")
        }
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let file = FileHandle(forWritingAtPath: path) else { return }
        file.seekToEndOfFile()
        file.write(data + Data("\n".utf8))
        try? file.close()
    }
}
