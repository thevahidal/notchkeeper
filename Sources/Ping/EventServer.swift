import Foundation
import Network

// Each hook connects and sends one JSON line. Most are disconnected right away;
// PermissionRequest stays connected until the app replies with one line.
final class EventServer {
    typealias Reply = (String) -> Void

    private let listener: NWListener
    private let onEvent: ([String: Any], Reply?) -> Void

    init(path: String, onEvent: @escaping ([String: Any], Reply?) -> Void) throws {
        self.onEvent = onEvent
        unlink(path)
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .unix(path: path)
        listener = try NWListener(using: params)
        // The socket file only exists once the listener is ready.
        listener.stateUpdateHandler = { state in
            if case .ready = state { chmod(path, 0o600) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            self?.read(connection, Data())
        }
        listener.start(queue: .main)
    }

    private func read(_ connection: NWConnection, _ received: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] chunk, _, isComplete, error in
            var data = received
            if let chunk { data.append(chunk) }
            // Real events are a few KB; a client that never sends a newline doesn't get to grow memory forever.
            if data.count > 1_000_000 { return connection.cancel() }
            guard data.contains(UInt8(ascii: "\n")) || isComplete || error != nil else {
                self?.read(connection, data)
                return
            }

            guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                connection.cancel()
                return
            }
            if event["hook_event_name"] as? String == "PermissionRequest" {
                self?.onEvent(event) { answer in
                    connection.send(content: Data((answer + "\n").utf8), completion: .contentProcessed { _ in connection.cancel() })
                }
            } else {
                connection.cancel()
                self?.onEvent(event, nil)
            }
        }
    }
}
