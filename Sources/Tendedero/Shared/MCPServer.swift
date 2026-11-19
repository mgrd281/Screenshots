import Foundation

/// Snapfly as a Model Context Protocol server, the way an AI app on the Mac,
/// like Claude, asks other apps for what it needs: JSON-RPC 2.0, one message
/// a line, over the standard input and output the AI app opened. It answers
/// the handshake, lists its tools, and hands each call to `call`. What a
/// tool returns is text and pictures; which tools there are, and what they
/// give, is Snapfly's own (`MCPMode` on the Mac).
final class MCPServer {
    /// One thing the AI app may ask for.
    struct Tool {
        let name: String
        let title: String
        let description: String
        /// The arguments it takes, as a JSON Schema object.
        var properties: [String: [String: Any]] = [:]
        var required: [String] = []

        var json: [String: Any] {
            var schema: [String: Any] = ["type": "object", "properties": properties]
            if !required.isEmpty { schema["required"] = required }
            return ["name": name, "title": title, "description": description, "inputSchema": schema,
                    "annotations": ["readOnlyHint": true, "openWorldHint": false]]
        }
    }

    /// A piece of what a tool gives back.
    enum Content: Equatable {
        case text(String)
        case image(Data, mimeType: String)

        var json: [String: Any] {
            switch self {
            case .text(let text): ["type": "text", "text": text]
            case .image(let data, let type): ["type": "image", "data": data.base64EncodedString(), "mimeType": type]
            }
        }
    }

    /// What a tool gives back, or why it could not.
    struct Result: Equatable {
        var content: [Content]
        var isError = false

        static func failure(_ text: String) -> Result { Result(content: [.text(text)], isError: true) }

        var json: [String: Any] { ["content": content.map(\.json), "isError": isError] }
    }

    /// The protocol's versions Snapfly speaks, newest first.
    static let versions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    let name: String
    let title: String
    let version: String
    let instructions: String
    let tools: [Tool]
    let call: (String, [String: Any]) -> Result

    init(name: String, title: String, version: String, instructions: String, tools: [Tool],
         call: @escaping (String, [String: Any]) -> Result) {
        self.name = name
        self.title = title
        self.version = version
        self.instructions = instructions
        self.tools = tools
        self.call = call
    }

    /// The answer to one line from the AI app, as one line, or nil where
    /// none is due, as for a notification.
    func respond(to line: String) -> String? {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) else {
            return Self.line(Self.error(-32700, "Parse error", id: NSNull()))
        }
        if let batch = object as? [Any] {
            let replies = batch.compactMap(answer)
            return replies.isEmpty ? nil : Self.line(replies)
        }
        return answer(object).flatMap { Self.line($0) }
    }

    /// The answer to one message, or nil for a notification or a response.
    func answer(_ message: Any) -> [String: Any]? {
        guard let message = message as? [String: Any] else {
            return Self.error(-32600, "Invalid Request", id: NSNull())
        }
        let id = message["id"]
        guard let method = message["method"] as? String else {
            // A response to something Snapfly never asks, or nothing at all.
            let isResponse = message["result"] != nil || message["error"] != nil
            return isResponse ? nil : Self.error(-32600, "Invalid Request", id: id ?? NSNull())
        }
        // A notification, like "notifications/initialized": nothing back.
        guard let id, !(id is NSNull) else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String
            let version = asked.flatMap { Self.versions.contains($0) ? $0 : nil } ?? Self.versions[0]
            return Self.reply(id, [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": name, "title": title, "version": self.version],
                "instructions": instructions,
            ])
        case "ping":
            return Self.reply(id, [:])
        case "tools/list":
            return Self.reply(id, ["tools": tools.map(\.json)])
        case "tools/call":
            guard let tool = params["name"] as? String, tools.contains(where: { $0.name == tool }) else {
                return Self.error(-32602, "Unknown tool", id: id)
            }
            return Self.reply(id, call(tool, params["arguments"] as? [String: Any] ?? [:]).json)
        default:
            return Self.error(-32601, "Method not found", id: id)
        }
    }

    private static func reply(_ id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private static func error(_ code: Int, _ message: String, id: Any) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    /// A message as one line of JSON: no line breaks, which end a message.
    private static func line(_ object: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
