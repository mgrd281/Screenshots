import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Tendedero

/// The AI assistant: what is sent to Claude or ChatGPT, how their answers
/// are read, and what their errors mean.
final class AIAssistantTests: XCTestCase {
    private let picture = AIImage(data: Data([0xFF, 0xD8, 0xFF]), mediaType: "image/jpeg")

    private func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    func testClaudeIsSentThePictureThenTheWords() throws {
        let body = AIRequest.body(.claude, model: "claude-opus-5-5", instructions: "Help.", text: "Write the reply.",
                                  image: picture)
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["system"] as? String, "Help.")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content.map { $0["type"] as? String }, ["image", "text"])
        let source = try XCTUnwrap(content[0]["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source["data"] as? String, picture.data.base64EncodedString())
        XCTAssertEqual(content[1]["text"] as? String, "Write the reply.")
        // The usual model takes an effort, and a declined request goes on to
        // another model on Anthropic's side.
        let output = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(output["effort"] as? String, "low")
        XCTAssertNil(output["format"])
        XCTAssertEqual(body["fallbacks"] as? String, "default")

        let request = try AIRequest.urlRequest(.claude, key: "sk-ant-test", body: body)
        XCTAssertEqual(request.url, URL(string: "https://api.anthropic.com/v1/messages"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(sent["model"] as? String, "claude-opus-5-5")
    }

    func testAnAnswerToBeReadComesAsJSON() throws {
        let body = AIRequest.body(.claude, model: "claude-opus-5-5", instructions: "Read.", text: "Read this order.",
                                  image: nil, schema: AITask.orderSchema)
        let content = try XCTUnwrap((body["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.map { $0["type"] as? String }, ["text"])
        let format = try XCTUnwrap((body["output_config"] as? [String: Any])?["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertNotNil(format["schema"] as? [String: Any])
    }

    func testAnotherClaudeModelIsSentOnlyWhatItTakes() throws {
        let body = AIRequest.body(.claude, model: "claude-haiku-4-5", instructions: "Help.", text: "Hi", image: nil)
        XCTAssertNil(body["output_config"])
        XCTAssertNil(body["fallbacks"])
        let request = try AIRequest.urlRequest(.claude, key: "k", body: body)
        XCTAssertNil(request.value(forHTTPHeaderField: "anthropic-beta"))
    }

    func testChatGPTIsSentTheWordsThenThePicture() throws {
        let body = AIRequest.body(.openAI, model: "gpt-6-sol", instructions: "Help.", text: "What is this?",
                                  image: picture, schema: AITask.orderSchema)
        XCTAssertEqual(body["model"] as? String, "gpt-6-sol")
        XCTAssertEqual(body["instructions"] as? String, "Help.")
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.map { $0["type"] as? String }, ["input_text", "input_image"])
        XCTAssertEqual(content[1]["image_url"] as? String, "data:image/jpeg;base64,\(picture.data.base64EncodedString())")
        let format = try XCTUnwrap((body["text"] as? [String: Any])?["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)
        XCTAssertNotNil(format["name"] as? String)

        let request = try AIRequest.urlRequest(.openAI, key: "sk-test", body: body)
        XCTAssertEqual(request.url, URL(string: "https://api.openai.com/v1/responses"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
    }

    func testClaudesAnswerIsItsTextWithoutItsThinking() throws {
        let data = try json(["stop_reason": "end_turn",
                             "content": [["type": "thinking", "thinking": ""],
                                         ["type": "text", "text": "Hallo, "], ["type": "text", "text": "danke!"]]])
        XCTAssertEqual(try AIRequest.answer(.claude, status: 200, data: data, model: "m"), "Hallo, danke!")
        let refused = try json(["stop_reason": "refusal", "content": []])
        XCTAssertThrowsError(try AIRequest.answer(.claude, status: 200, data: refused, model: "m")) {
            XCTAssertEqual($0 as? AIError, .refused)
        }
        let empty = try json(["stop_reason": "end_turn", "content": []])
        XCTAssertThrowsError(try AIRequest.answer(.claude, status: 200, data: empty, model: "m"))
    }

    func testChatGPTsAnswerIsItsMessageText() throws {
        let data = try json(["output": [["type": "reasoning", "summary": []],
                                        ["type": "message", "content": [["type": "output_text", "text": "It is an order."]]]]])
        XCTAssertEqual(try AIRequest.answer(.openAI, status: 200, data: data, model: "m"), "It is an order.")
        let refused = try json(["output": [["type": "message", "content": [["type": "refusal", "refusal": "No."]]]]])
        XCTAssertThrowsError(try AIRequest.answer(.openAI, status: 200, data: refused, model: "m")) {
            XCTAssertEqual($0 as? AIError, .refused)
        }
    }

    func testEachFailureSaysWhatToDo() throws {
        func failure(_ status: Int, _ error: [String: Any]) -> AIError {
            AIRequest.error(status: status, json: ["error": error], model: "gpt-x")
        }
        XCTAssertEqual(failure(401, ["type": "authentication_error", "message": "invalid x-api-key"]), .badKey)
        XCTAssertEqual(failure(400, ["type": "invalid_request_error",
                                     "message": "Your credit balance is too low to access the Anthropic API."]), .noCredit)
        XCTAssertEqual(failure(429, ["code": "insufficient_quota", "message": "You exceeded your current quota."]), .noCredit)
        XCTAssertEqual(failure(429, ["type": "rate_limit_error", "message": "Too many requests"]), .busy)
        XCTAssertEqual(failure(529, ["type": "overloaded_error", "message": "Overloaded"]), .busy)
        XCTAssertEqual(failure(404, ["type": "not_found_error", "message": "model: gpt-x"]), .unknownModel("gpt-x"))
        XCTAssertEqual(failure(400, ["message": "The model `gpt-x` does not exist"]), .unknownModel("gpt-x"))
        XCTAssertEqual(failure(400, ["message": "Bad image"]), .other("Bad image"))
        XCTAssertEqual(AIRequest.error(status: 500, json: [:], model: "m"), .busy)
        // Settings fixes a key or a model; time fixes the rest.
        XCTAssertTrue(AIError.badKey.isSettings)
        XCTAssertTrue(AIError.unknownModel("x").isSettings)
        XCTAssertFalse(AIError.busy.isSettings)
    }

    func testTheOrderIsReadFromTheAnswer() {
        let parts = AITask.orderParts(from: """
            {"order": "MR1YLF5", "date": "09.07.2026", "total": "57,80 €",
             "product": "2 × Office 2024 Professional Plus", "tracking": " "}
            """)
        XCTAssertEqual(parts[.order], "MR1YLF5")
        XCTAssertEqual(parts[.total], "57,80 €")
        XCTAssertEqual(parts[.product], "2 × Office 2024 Professional Plus")
        // Empty, it is left out.
        XCTAssertNil(parts[.tracking])
        XCTAssertTrue(AITask.orderParts(from: "Not JSON").isEmpty)
    }

    func testAKeyIsShownOnlyByItsEnd() {
        XCTAssertEqual(AIAccount.hint(for: "sk-ant-api03-abcdWXYZ"), "…WXYZ")
    }

    func testEveryProviderHasItsOwnPlaces() {
        XCTAssertEqual(AIProvider.claude.defaultModel, "claude-opus-5-5")
        XCTAssertEqual(AIProvider.allCases.map(\.name), ["Claude", "ChatGPT"])
        for provider in AIProvider.allCases {
            XCTAssertEqual(provider.keyPage.scheme, "https")
            XCTAssertEqual(provider.endpoint.scheme, "https")
        }
    }

    func testAPictureIsSentSmallerAsJPEG() throws {
        let width = 3000, height = 1000
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ai-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let sent = try XCTUnwrap(AIImage.from(url))
        XCTAssertEqual(sent.mediaType, "image/jpeg")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(sent.data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 2000)
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
    }
}
