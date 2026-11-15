import Foundation

// A quick read of how dangerous a tool call looks, shown on the approval card before you allow it.
// Heuristics only: green means nothing matched, not that the call is safe.
struct Risk {
    enum Level: Int { case low, medium, high }
    var level = Level.low
    var reasons: [String] = []

    // Keeps only the reasons for the highest level seen.
    private mutating func flag(_ level: Level, _ reason: String) {
        if level.rawValue > self.level.rawValue {
            self.level = level
            reasons = []
        }
        if level == self.level && !reasons.contains(reason) { reasons.append(reason) }
    }

    private static let high: [(String, String)] = [
        (#"\brm\s+(-\S+\s+)*(/|~|\$HOME|\*|\.\.?(\s|$))"#, "deletes outside the project or everything"),
        (#"\bsudo\b"#, "runs as root"),
        (#"(curl|wget)[^|]*\|\s*(sudo\s+)?(sh|bash|zsh|python3?)\b"#, "runs a downloaded script"),
        (#"\bgit\s+push\b.*(\s-f\b|--force)"#, "force-pushes"),
        (#"\bgit\s+(reset\s+--hard|clean\s+-[a-zA-Z]*f)"#, "discards local changes"),
        (#"\bchmod\s+(-R\s+)?777\b"#, "opens permissions to everyone"),
        (#"\b(mkfs|diskutil\s+erase|dd\s+if=)"#, "writes to a disk"),
        (#"(\.ssh/|\.aws/|\.gnupg/|id_rsa|id_ed25519|\.netrc|keychain|security\s+find-)"#, "touches keys or credentials"),
        (#"(^|[\s;&|])(printenv|env)(\s*$|\s*\|)"#, "dumps environment variables"),
    ]

    private static let medium: [(String, String)] = [
        (#"(^|[\s;&|(])(curl|wget|ssh|scp|rsync|nc|ftp)\s"#, "uses the network"),
        (#"\bgit\s+push\b"#, "pushes to a remote"),
        (#"\b(npm|pnpm|yarn)\s+publish\b"#, "publishes a package"),
        (#"\b(npm|pnpm|yarn|bun)\s+(i|install|add)\b|\bpip3?\s+install\b|\bbrew\s+install\b|\bgem\s+install\b|\bcargo\s+install\b"#, "installs packages"),
        (#"\brm\s+(-\S+\s+)*-[a-zA-Z]*[rR]"#, "deletes folders"),
        (#"\brm\b(?!\s+(-\S+\s+)*-[a-zA-Z]*[rR])"#, "deletes files"),
        (#"\b(kill|pkill|killall)\b"#, "stops processes"),
        (#"\bdocker\s+(run|rm|rmi|system\s+prune)"#, "changes containers"),
        (#"\.env\b"#, "touches a .env file"),
        (#"\b(DROP|TRUNCATE)\s+(TABLE|DATABASE)\b|\bmigrate\b"#, "changes a database"),
    ]

    private static let sensitiveFiles = [
        ".env", ".ssh/", ".aws/", ".gnupg/", "id_rsa", "id_ed25519", ".netrc", ".npmrc", ".pypirc",
        ".zshrc", ".bashrc", ".bash_profile", ".profile", ".gitconfig", ".git/hooks/", ".git/config",
        ".claude/settings", "Library/LaunchAgents/", "/etc/",
    ]

    init() {}

    init(tool: String, input: [String: Any], cwd: String) {
        if let command = input["command"] as? String {
            for (pattern, reason) in Self.high where Self.matches(command, pattern) { flag(.high, reason) }
            for (pattern, reason) in Self.medium where Self.matches(command, pattern) { flag(.medium, reason) }
        }
        if let path = input["file_path"] as? String ?? input["notebook_path"] as? String {
            let full = (path as NSString).standardizingPath
            if Self.sensitiveFiles.contains(where: { full.contains($0) }) { flag(.high, "edits a sensitive file") }
            let root = (cwd as NSString).standardizingPath
            if !cwd.isEmpty && !full.hasPrefix(root + "/") { flag(.medium, "outside the project") }
        }
        if tool == "WebFetch" || tool == "WebSearch" { flag(.medium, "uses the network") }
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
