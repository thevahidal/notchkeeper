import Foundation

// `notchkeeper notify` and `notchkeeper run`: put anything in the notch, not just agents.
// They talk to the app over the same private socket as the hooks.
enum Items {
    static let usage = """
        usage: notchkeeper notify --id ID --title TITLE [--state working|needs-you|done|remove] [--detail TEXT] [--url URL] [--source NAME]
               notchkeeper run [--title TITLE] -- COMMAND [ARGS...]
        """

    // Returns the exit code for the process.
    static func main(_ args: [String]) -> Int32 {
        switch args.first {
        case "notify":
            guard let event = notifyEvent(Array(args.dropFirst())) else { return fail(usage) }
            return send(event) ? 0 : fail("Notchkeeper isn't running.")
        case "run":
            return run(Array(args.dropFirst()))
        default:
            return fail(usage)
        }
    }

    private static func notifyEvent(_ args: [String]) -> [String: Any]? {
        var options: [String: String] = [:]
        var i = 0
        while i + 1 < args.count, args[i].hasPrefix("--") {
            options[String(args[i].dropFirst(2))] = args[i + 1]
            i += 2
        }
        guard i == args.count, let id = options["id"], let title = options["title"] else { return nil }
        return event(id: id, title: title, state: options["state"] ?? "working", detail: options["detail"] ?? "",
                     url: options["url"], source: options["source"] ?? "notify")
    }

    static func event(id: String, title: String, state: String, detail: String, url: String?, source: String) -> [String: Any] {
        var event: [String: Any] = ["hook_event_name": "Item", "session_id": "item:\(source):\(id)", "source": source,
                                    "title": title, "state": state, "detail": detail, "cwd": FileManager.default.currentDirectoryPath]
        if let url { event["url"] = url }
        return event
    }

    // Runs the command in your terminal as usual, and tells the notch when it starts and how it ended.
    private static func run(_ args: [String]) -> Int32 {
        var args = args
        var title: String?
        if args.first == "--title", args.count > 1 { title = args[1]; args.removeFirst(2) }
        if args.first == "--" { args.removeFirst() }
        guard let command = args.first else { return fail(usage) }
        let name = title ?? args.joined(separator: " ")
        let id = String(UUID().uuidString.prefix(8))
        let started = Date()
        send(event(id: id, title: name, state: "working", detail: "Running", url: nil, source: "run"))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args.dropFirst()
        do { try process.run() } catch { return fail("couldn't run \(command): \(error.localizedDescription)") }
        // Ctrl-C reaches the child through the terminal; we just wait for it.
        signal(SIGINT, SIG_IGN)
        process.waitUntilExit()

        let took = duration(Date().timeIntervalSince(started))
        let code = process.terminationStatus
        send(event(id: id, title: name, state: code == 0 ? "done" : "needs-you",
                   detail: code == 0 ? "Finished in \(took)" : "Failed with exit \(code) after \(took)", url: nil, source: "run"))
        return code
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return s < 60 ? "\(s)s" : s < 3600 ? "\(s / 60)m \(s % 60)s" : "\(s / 3600)h \(s % 3600 / 60)m"
    }

    @discardableResult
    static func send(_ event: [String: Any]) -> Bool {
        guard var data = try? JSONSerialization.data(withJSONObject: event) else { return false }
        data.append(UInt8(ascii: "\n"))
        let path = HookInstaller.home + "/.notchkeeper/notchkeeper.sock"
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8.prefix(MemoryLayout.size(ofValue: address.sun_path) - 1))
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0, data.withUnsafeBytes({ write(fd, $0.baseAddress, data.count) }) == data.count else { return false }
        // Like nc: say we're done writing, then wait (up to a second) for the app to read and hang up.
        // Closing straight away can drop the message before the app reads it.
        shutdown(fd, SHUT_WR)
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var byte: UInt8 = 0
        _ = read(fd, &byte, 1)
        return true
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 2
    }
}
