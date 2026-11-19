import XCTest
@testable import Tendedero

/// Snapfly as an MCP server: the handshake, the tools, a call, and what
/// is no request; and text covered as an AI app is given it.
final class MCPServerTests: XCTestCase {
    private func server(_ calls: @escaping (String, [String: Any]) -> MCPServer.Result = { _, _ in
        MCPServer.Result(content: [.text("done")])
    }) -> MCPServer {
        MCPServer(name: "snapfly", title: "Snapfly", version: "1.1.0", instructions: "Covered.",
                  tools: [MCPServer.Tool(name: "cover_text", title: "Cover Text", description: "Covers text.",
                                         properties: ["text": ["type": "string"]], required: ["text"])],
                  call: calls)
    }

    private func object(_ line: String?) throws -> [String: Any] {
        let line = try XCTUnwrap(line)
        XCTAssertFalse(line.contains("\n"), "One message, one line")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    func testTheHandshakeAnswersInTheVersionAsked() throws {
        let reply = try object(server().respond(to:
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{}}}"#))
        XCTAssertEqual(reply["id"] as? Int, 1)
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "snapfly")
        XCTAssertEqual(result["instructions"] as? String, "Covered.")
    }

    func testAVersionUnknownIsAnsweredWithTheNewest() throws {
        let reply = try object(server().respond(to:
            #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#))
        XCTAssertEqual(reply["id"] as? String, "a")
        XCTAssertEqual((reply["result"] as? [String: Any])?["protocolVersion"] as? String, MCPServer.versions[0])
    }

    func testTheToolsAreListedWithTheirArguments() throws {
        let reply = try object(server().respond(to: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        let tools = try XCTUnwrap((reply["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0]["name"] as? String, "cover_text")
        let schema = try XCTUnwrap(tools[0]["inputSchema"] as? [String: Any])
        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertEqual(schema["required"] as? [String], ["text"])
    }

    func testACallIsHandedOnWithItsArguments() throws {
        var asked: (String, String?)?
        let mcp = server { name, arguments in
            asked = (name, arguments["text"] as? String)
            return MCPServer.Result(content: [.text("[NAME 1]"), .image(Data([1, 2, 3]), mimeType: "image/jpeg")])
        }
        let reply = try object(mcp.respond(to:
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cover_text","arguments":{"text":"Hi"}}}"#))
        XCTAssertEqual(asked?.0, "cover_text")
        XCTAssertEqual(asked?.1, "Hi")
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["text"] as? String, "[NAME 1]")
        XCTAssertEqual(content[1]["type"] as? String, "image")
        XCTAssertEqual(content[1]["data"] as? String, Data([1, 2, 3]).base64EncodedString())
        XCTAssertEqual(content[1]["mimeType"] as? String, "image/jpeg")
    }

    func testAnUnknownToolOrMethodIsAnError() throws {
        let tool = try object(server().respond(to:
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"read_mail"}}"#))
        XCTAssertEqual((tool["error"] as? [String: Any])?["code"] as? Int, -32602)
        let method = try object(server().respond(to: #"{"jsonrpc":"2.0","id":5,"method":"resources/list"}"#))
        XCTAssertEqual((method["error"] as? [String: Any])?["code"] as? Int, -32601)
        let broken = try object(server().respond(to: "{not json"))
        XCTAssertEqual((broken["error"] as? [String: Any])?["code"] as? Int, -32700)
    }

    func testANotificationGetsNoAnswer() throws {
        XCTAssertNil(server().respond(to: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
        XCTAssertNil(server().respond(to: "   "))
        let ping = try object(server().respond(to: #"{"jsonrpc":"2.0","id":6,"method":"ping"}"#))
        XCTAssertNotNil(ping["result"] as? [String: Any])
    }

    // MARK: Text

    func testDetailsInTextBecomeTagsNumberedByWhatTheyAre() {
        let text = "Please write to anna.berg@example.com today.\nOr call +49 151 23456789.\nAgain: anna.berg@example.com"
        let covered = TextCover.covered(text, [.emails, .phones], rules: [])
        XCTAssertFalse(covered.text.contains("anna.berg@example.com"))
        XCTAssertFalse(covered.text.contains("23456789"))
        XCTAssertTrue(covered.text.contains("Please write to [EMAIL 1] today."), covered.text)
        XCTAssertTrue(covered.text.contains("Again: [EMAIL 1]"), covered.text)
        XCTAssertTrue(covered.text.contains("[PHONE 1]"), covered.text)
        XCTAssertGreaterThanOrEqual(covered.count, 3)
        // The lines stay as they were.
        XCTAssertEqual(covered.text.components(separatedBy: "\n").count, 3)
    }

    func testTheOwnersOwnNameIsCoveredWhateverIsChosen() {
        let me = OwnRule(text: OwnDetails.nameText(given: "Max", surname: "Mustermann"), kind: .name)
        let covered = TextCover.covered("Thanks, Max Mustermann", [], rules: [me])
        XCTAssertFalse(covered.text.contains("Mustermann"), covered.text)
        XCTAssertEqual(covered.count, 1)
    }

    func testTextWithNothingPrivateStaysAsItIs() {
        let covered = TextCover.covered("The parcel is on its way.", [.emails, .phones], rules: [])
        XCTAssertEqual(covered, TextCover.Covered(text: "The parcel is on its way.", count: 0))
    }

    func testPlacesThatOverlapAreOne() {
        let places: [(range: NSRange, kind: PrivateDetail?)] = [
            (NSRange(location: 10, length: 5), .phones), (NSRange(location: 0, length: 4), .names),
            (NSRange(location: 3, length: 4), .addresses),
        ]
        let merged = TextCover.merged(places)
        XCTAssertEqual(merged.map(\.range), [NSRange(location: 0, length: 7), NSRange(location: 10, length: 5)])
        XCTAssertEqual(merged.map(\.kind), [.names, .phones])
    }
}

/// Connect to Claude: Snapfly among Claude's MCP servers, everything else
/// in Claude's settings kept, and settings that cannot be read left alone.
final class ClaudeConnectTests: XCTestCase {
    private let command = "/Applications/Snapfly.app/Contents/MacOS/Snapfly"

    private func settings(_ data: Data?) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
    }

    func testSnapflyIsAddedToNoSettingsYet() throws {
        let made = try settings(ClaudeConnect.merged(nil, command: command))
        let snapfly = try XCTUnwrap((made["mcpServers"] as? [String: Any])?["snapfly"] as? [String: Any])
        XCTAssertEqual(snapfly["command"] as? String, command)
        XCTAssertEqual(snapfly["args"] as? [String], ["--mcp"])
        XCTAssertTrue(ClaudeConnect.contains(try XCTUnwrap(ClaudeConnect.merged(Data("  \n".utf8), command: command)),
                                             command: command))
    }

    func testEverythingElseInClaudesSettingsIsKept() throws {
        let before = #"{"globalShortcut":"Cmd+Space","mcpServers":{"files":{"command":"npx","args":["-y","files"]}}}"#
        let made = try settings(ClaudeConnect.merged(Data(before.utf8), command: command))
        XCTAssertEqual(made["globalShortcut"] as? String, "Cmd+Space")
        let servers = try XCTUnwrap(made["mcpServers"] as? [String: Any])
        XCTAssertEqual(Set(servers.keys), ["files", "snapfly"])
        XCTAssertEqual((servers["files"] as? [String: Any])?["command"] as? String, "npx")
    }

    func testSettingsThatCannotBeReadAreLeftAlone() {
        XCTAssertNil(ClaudeConnect.merged(Data("{ broken".utf8), command: command))
        XCTAssertNil(ClaudeConnect.merged(Data(#"["not", "settings"]"#.utf8), command: command))
        XCTAssertNil(ClaudeConnect.merged(Data(#"{"mcpServers":"none"}"#.utf8), command: command))
    }

    func testConnectedOnlyWhenClaudeStartsThisSnapfly() throws {
        let made = try XCTUnwrap(ClaudeConnect.merged(nil, command: command))
        XCTAssertTrue(ClaudeConnect.contains(made, command: command))
        XCTAssertFalse(ClaudeConnect.contains(made, command: "/Applications/Other.app/Contents/MacOS/Other"))
        XCTAssertFalse(ClaudeConnect.contains(Data(#"{"mcpServers":{}}"#.utf8), command: command))
    }
}
