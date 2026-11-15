import Foundation

// The last few turns of a Claude session, read from its transcript, for the reply card.
struct ChatLine: Identifiable {
    enum Role { case you, claude, tool }
    let id: Int
    let role: Role
    let text: String
}

enum Chat {
    // Only the end of the file: transcripts grow to many megabytes.
    static func read(_ path: String, limit: Int = 14) -> [ChatLine] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 400_000 ? size - 400_000 : 0)
        let text = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)

        var lines: [ChatLine] = []
        for raw in text.split(separator: "\n") {
            guard raw.contains("\"type\":\"user\"") || raw.contains("\"type\":\"assistant\""),
                  let entry = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
                  entry["isSidechain"] as? Bool != true, entry["isMeta"] as? Bool != true,
                  let message = entry["message"] as? [String: Any] else { continue }
            let blocks = (message["content"] as? [[String: Any]]) ?? (message["content"] as? String).map { [["type": "text", "text": $0]] } ?? []
            let isUser = entry["type"] as? String == "user"
            for block in blocks {
                switch block["type"] as? String {
                case "text":
                    // Injected context (<system-reminder>, <command-name>, …) isn't something anyone typed.
                    guard let body = (block["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !body.isEmpty, !body.hasPrefix("<") else { continue }
                    lines.append(ChatLine(id: lines.count, role: isUser ? .you : .claude, text: String(body.prefix(1200))))
                case "tool_use" where !isUser:
                    let name = (block["name"] as? String ?? "").components(separatedBy: "__").last ?? ""
                    let input = block["input"] as? [String: Any] ?? [:]
                    let target = input["command"] as? String ?? (input["file_path"] as? String).map { ($0 as NSString).lastPathComponent }
                        ?? input["pattern"] as? String ?? input["description"] as? String
                    lines.append(ChatLine(id: lines.count, role: .tool, text: target.map { "\(name): \($0)" } ?? name))
                default: continue
                }
            }
        }
        return Array(lines.suffix(limit))
    }
}
