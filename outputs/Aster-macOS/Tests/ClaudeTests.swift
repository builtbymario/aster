import Foundation
import XCTest
@testable import Aster

/// Answers model lookups with a fixed profile and serves queued responses to everything else.
final class ClaudeMockProtocol: URLProtocol {
    static var responses: [(Int, String)] = []
    static var requests: [URLRequest] = []
    static var bodies: [[String: Any]] = []
    static func reset(_ responses: [(Int, String)]) { self.responses = responses; requests = []; bodies = [] }
    static let profile = #"{"id":"claude-test","display_name":"Claude Test","max_tokens":32000,"capabilities":{"effort":{"supported":true},"image_input":{"supported":true}}}"#
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(buffer, count: count) }
        }
        let (status, text): (Int, String)
        if request.url?.path.contains("/models/") == true { (status, text) = (200, Self.profile) }
        else {
            Self.requests.append(request); Self.bodies.append((try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
            (status, text) = Self.responses.isEmpty ? (500, #"{"type":"error","error":{"type":"api_error","message":"Missing fixture"}}"#) : Self.responses.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ClaudeTests: XCTestCase {
    static func api() throws -> AnthropicAPI {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ClaudeMockProtocol.self]
        return try AnthropicAPI(apiKey: "test-claude-key", baseURL: "https://claude.test/v1", transport: URLSession(configuration: config))
    }
    static func request(model: String = "claude-opus-5-5", images: [Data] = []) -> ChatTurnRequest {
        var settings = IntelligenceSettings(); settings.automaticMemory = false
        return ChatTurnRequest(model: model, effort: QuickChat.effort, instructions: QuickChat.instructions(for: Specialist.defaults[0], settings: settings),
                               history: [.init(role: "user", text: "Hola"), .init(role: "assistant", text: "¿En qué te ayudo?")], input: "¿Qué tengo mañana?",
                               tools: AgentAPI.functionTools(settings: settings), webSearch: true, images: images)
    }
    static func message(_ blocks: [[String: Any]], stop: String) -> String {
        var events: [[String: Any]] = [["type": "message_start", "message": ["id": "msg_1", "type": "message", "role": "assistant", "content": []]]]
        for (index, block) in blocks.enumerated() {
            var start = block; var deltas: [[String: Any]] = []
            switch block["type"] as? String {
            case "text": start["text"] = ""; deltas = [["type": "text_delta", "text": block["text"] as? String ?? ""]]
            case "thinking": start["thinking"] = ""; start["signature"] = ""; deltas = [["type": "signature_delta", "signature": block["signature"] as? String ?? ""]]
            case "tool_use": start["input"] = [String: Any](); deltas = (block["partial"] as? [String] ?? []).map { ["type": "input_json_delta", "partial_json": $0] }; start["partial"] = nil
            default: break
            }
            events.append(["type": "content_block_start", "index": index, "content_block": start])
            events += deltas.map { ["type": "content_block_delta", "index": index, "delta": $0] }
            events.append(["type": "content_block_stop", "index": index])
        }
        events += [["type": "message_delta", "delta": ["stop_reason": stop], "usage": ["output_tokens": 12]], ["type": "message_stop"]]
        return events.map { "event: \($0["type"] as! String)\ndata: " + String(decoding: try! JSONSerialization.data(withJSONObject: $0), as: UTF8.self) + "\n\n" }.joined()
    }

    @MainActor func testStreamsTextAndRunsToolsTheClaudeWay() async throws {
        ClaudeMockProtocol.reset([
            (200, Self.message([["type": "thinking", "signature": "sig-1"], ["type": "text", "text": "Miro tu calendario."],
                                ["type": "tool_use", "id": "toolu_1", "name": "aster_calendar", "partial": [#"{"operation":"#, #""list","days":2}"#]]], stop: "tool_use")),
            (200, Self.message([["type": "text", "text": "Mañana tienes dos citas."]], stop: "end_turn"))
        ])
        var calls: [PendingToolCall] = []; var streamed = ""
        let answer = try await AnthropicChatProvider(api: Self.api()).respond(Self.request(images: [Data("screen".utf8)]), toolHandler: { call in calls.append(call); return #"{"events":2}"# }, onEvent: { event in if case .text(_, let delta) = event { streamed += delta } })
        XCTAssertEqual(answer, "Miro tu calendario.\n\nMañana tienes dos citas.")
        XCTAssertEqual(streamed, "Miro tu calendario.Mañana tienes dos citas.", "Text streams as it arrives")
        XCTAssertEqual(calls.map(\.name), ["aster_calendar"]); XCTAssertEqual(calls.first?.arguments["days"] as? Int, 2)

        let headers = try XCTUnwrap(ClaudeMockProtocol.requests.first)
        XCTAssertEqual(headers.value(forHTTPHeaderField: "x-api-key"), "test-claude-key")
        XCTAssertEqual(headers.value(forHTTPHeaderField: "anthropic-version"), "2026-10-21")
        XCTAssertEqual(headers.value(forHTTPHeaderField: "anthropic-beta"), "server-side-fallback-2026-07-01")
        let first = ClaudeMockProtocol.bodies[0]
        XCTAssertEqual(first["stream"] as? Bool, true); XCTAssertEqual(first["fallbacks"] as? String, "default")
        XCTAssertNil(first["temperature"]); XCTAssertNil(first["thinking"], "Thinking stays adaptive; it cannot be turned off on current models")
        XCTAssertEqual((first["output_config"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertEqual(first["max_tokens"] as? Int, 32000, "Never above what the model allows")
        let tools = try XCTUnwrap(first["tools"] as? [[String: Any]])
        XCTAssertTrue(tools.contains { $0["name"] as? String == "aster_mail" && $0["eager_input_streaming"] as? Bool == true && $0["input_schema"] != nil })
        XCTAssertTrue(tools.contains { $0["type"] as? String == "web_search_20260209" })
        let opening = try XCTUnwrap(first["messages"] as? [[String: Any]])
        XCTAssertEqual(opening.map { $0["role"] as? String }, ["user", "assistant", "user"])
        let question = try XCTUnwrap(opening.last?["content"] as? [[String: Any]])
        XCTAssertEqual(question.map { $0["type"] as? String }, ["image", "text"], "The screenshot goes before the question")

        let second = try XCTUnwrap(ClaudeMockProtocol.bodies[1]["messages"] as? [[String: Any]])
        let echoed = try XCTUnwrap(second[second.count - 2]["content"] as? [[String: Any]])
        XCTAssertEqual(echoed.map { $0["type"] as? String }, ["thinking", "text", "tool_use"], "The model's own blocks go back unchanged")
        XCTAssertEqual(echoed[0]["signature"] as? String, "sig-1")
        XCTAssertEqual((echoed[2]["input"] as? [String: Any])?["operation"] as? String, "list")
        let results = try XCTUnwrap(second.last?["content"] as? [[String: Any]])
        XCTAssertEqual(results.first?["tool_use_id"] as? String, "toolu_1"); XCTAssertEqual(results.first?["content"] as? String, #"{"events":2}"#)
    }

    @MainActor func testBrokenOrInvalidToolInputIsNeverRun() async throws {
        ClaudeMockProtocol.reset([
            (200, Self.message([["type": "tool_use", "id": "toolu_bad", "name": "aster_calendar", "partial": [#"{"operation": "list""#]],
                                ["type": "tool_use", "id": "toolu_missing", "name": "aster_mail", "partial": [#"{"query":"factura"}"#]],
                                ["type": "tool_use", "id": "toolu_enum", "name": "aster_notes", "partial": [#"{"operation":"delete"}"#]]], stop: "tool_use")),
            (200, Self.message([["type": "text", "text": "No he podido leerlo."]], stop: "end_turn"))
        ])
        var ran = 0
        _ = try await AnthropicChatProvider(api: Self.api()).respond(Self.request(), toolHandler: { _ in ran += 1; return "{}" }, onEvent: { _ in })
        XCTAssertEqual(ran, 0)
        let results = try XCTUnwrap((ClaudeMockProtocol.bodies[1]["messages"] as? [[String: Any]])?.last?["content"] as? [[String: Any]])
        XCTAssertEqual(results.count, 3, "Every call gets an answer, in one message")
        XCTAssertTrue(results.allSatisfy { $0["is_error"] as? Bool == true })
        XCTAssertTrue((results[0]["content"] as? String ?? "").contains("INVALID_JSON"))
        XCTAssertTrue((results[1]["content"] as? String ?? "").contains("operation"))
        XCTAssertTrue((results[2]["content"] as? String ?? "").contains("search, read, create"))
    }

    @MainActor func testRefusalsTruncatedActionsAndErrorsReadWell() async throws {
        ClaudeMockProtocol.reset([(200, Self.message([["type": "text", "text": "Lo siento"]], stop: "refusal"))])
        do { _ = try await AnthropicChatProvider(api: Self.api()).respond(Self.request(), toolHandler: { _ in "" }, onEvent: { _ in }); XCTFail("A refusal is not an answer") }
        catch { XCTAssertEqual(error.localizedDescription, AnthropicAPI.refusal) }

        ClaudeMockProtocol.reset([(200, Self.message([["type": "tool_use", "id": "toolu_cut", "name": "aster_notes", "partial": [#"{"operation":"create","body":"Acta"#]]], stop: "max_tokens"))])
        var ran = false
        do { _ = try await AnthropicChatProvider(api: Self.api()).respond(Self.request(), toolHandler: { _ in ran = true; return "" }, onEvent: { _ in }); XCTFail("A cut action must not run") }
        catch { XCTAssertFalse(ran) }

        ClaudeMockProtocol.reset([(401, #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key test-claude-key"}}"#)])
        do { _ = try await AnthropicChatProvider(api: Self.api()).respond(Self.request(), toolHandler: { _ in "" }, onEvent: { _ in }); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("Ajustes → Conexiones")); XCTAssertFalse(error.localizedDescription.contains("test-claude-key"), "The key never shows in errors") }

        ClaudeMockProtocol.reset([(400, #"{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API."}}"#)])
        do { _ = try await AnthropicChatProvider(api: Self.api()).respond(Self.request(), toolHandler: { _ in "" }, onEvent: { _ in }); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("facturación")) }
    }

    func testOnlyTheFallbackModelsBlocksGoBack() {
        let blocks: [[String: Any]] = [["type": "thinking", "signature": "old"], ["type": "text", "text": "Empiezo"], ["type": "tool_use", "id": "t1", "name": "aster_notes", "input": [:]],
                                       ["type": "fallback", "from": ["model": "claude-opus-5-5"], "to": ["model": "claude-opus-5"]], ["type": "text", "text": "Sigo"], ["type": "tool_use", "id": "t2", "name": "aster_notes", "input": [:]]]
        let kept = AnthropicAPI.afterFallback(blocks)
        XCTAssertEqual(kept.map { $0["type"] as? String }, ["text", "text", "tool_use"])
        XCTAssertEqual(kept.last?["id"] as? String, "t2", "Only the model that finished the turn acts")
    }

    func testTheConversationAlwaysStartsWithTheUserAndAlternates() {
        let messages = AnthropicChatProvider.messages(history: [.init(role: "assistant", text: "Tu web está lista."), .init(role: "assistant", text: "¿Seguimos?"), .init(role: "user", text: "Sí")],
                                                      question: [["type": "text", "text": "Publícala"]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["user", "assistant", "user"])
        XCTAssertEqual((messages[1]["content"] as? [[String: Any]])?.count, 2, "Two answers in a row are joined")
        XCTAssertEqual((messages[2]["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }, ["Sí", "Publícala"])
    }

    @MainActor func testClaudeDecidesEachStepOnTheMacFromTheLatestScreen() async throws {
        let step: (String) -> String = { action in
            #"{"id":"msg","type":"message","role":"assistant","stop_reason":"tool_use","content":[{"type":"thinking","thinking":"","signature":"s"},{"type":"tool_use","id":"toolu_d","name":"aster_desktop","input":{"action":"\#(action)","explanation":"Abro Numbers","app":"Numbers","sensitive":false}}]}"#
        }
        ClaudeMockProtocol.reset([(200, step("open_app")), (200, step("observe"))])
        let planner = ClaudeDesktopPlanner(api: try Self.api(), model: "claude-opus-5-5", effort: "medium", instructions: "Operate the Mac.", task: "Crea un presupuesto en Numbers")
        let frame = DesktopFrame(jpeg: Data("frame".utf8), geometry: ScreenGeometry(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800), imageWidth: 1000, imageHeight: 800), context: "Finder")
        let first = try await planner.next(frame, reply: "")
        XCTAssertEqual(first.action.action, "open_app"); XCTAssertEqual(first.action.app, "Numbers")
        planner.report(first.call, "Action posted.")
        _ = try await planner.next(frame, reply: "Usa la plantilla en blanco")
        let body = ClaudeMockProtocol.bodies[1]
        XCTAssertEqual((body["tool_choice"] as? [String: Any])?["type"] as? String, "auto", "Current models do not accept a forced tool")
        let content = try XCTUnwrap((body["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.filter { $0["type"] as? String == "image" }.count, 1, "Only the latest screenshot is sent")
        let text = content.last?["text"] as? String ?? ""
        XCTAssertTrue(text.contains("Crea un presupuesto en Numbers") && text.contains("1. open_app: Abro Numbers → Action posted.") && text.contains("Usa la plantilla en blanco"))
    }

    func testModelChoices() {
        XCTAssertEqual(AIProvider.label("claude-opus-5-5"), "Claude Opus 5.5")
        XCTAssertEqual(AIProvider.label("claude-haiku-4-5-20251001"), "Claude Haiku 4.5")
        XCTAssertEqual(AIProvider.label("gpt-6-astra"), "gpt-6-astra")
        XCTAssertEqual(AIProvider.preferredModel(["claude-sonnet-5-5", "claude-opus-5-5"], provider: .anthropic, current: nil), "claude-opus-5-5")
        XCTAssertEqual(AIProvider.preferredModel(["claude-sonnet-5-5"], provider: .anthropic, current: "claude-sonnet-5-5"), "claude-sonnet-5-5", "A choice the key can use is kept")
        XCTAssertEqual(AIProvider.chatModels(["gpt-6-astra", "gpt-4o-mini-tts", "text-embedding-3", "o4-mini", "gpt-realtime"], provider: .openai, keeping: nil), ["gpt-6-astra", "o4-mini"])
        var settings = IntelligenceSettings(); XCTAssertEqual(settings.chatModel, settings.model, "OpenAI stays the default")
        settings.provider = "anthropic"; XCTAssertEqual(settings.workModel, AnthropicAPI.defaultModel); XCTAssertEqual(settings.providerName, "Claude")
    }

    @MainActor func testWithClaudeMissionsRunOnThisMac() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aster-claude-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let provider = ScriptedChatProvider { _, _, event in event(.text("m", "# Plan de marketing\nTres canales.")); return "" }
        let store = AsterStore(directory: folder, startServices: false, apiFactory: { throw AsterError.message("OpenAI is not used") }, chatFactory: { provider })
        var settings = store.settings; settings.provider = "anthropic"; settings.effort = "high"; store.settings = settings
        store.attachments = [Attachment(name: "notas.txt", data: Data("Público: estudiantes".utf8))]
        XCTAssertTrue(store.run("Haz un plan de marketing"))
        for _ in 0..<100 where store.busy { try await Task.sleep(for: .milliseconds(10)) }
        let mission = try XCTUnwrap(store.state.missions.first)
        XCTAssertEqual(mission.engine, "direct"); XCTAssertEqual(mission.status, "Completada")
        XCTAssertEqual(mission.messages.last?.text, "# Plan de marketing\nTres canales.")
        let request = try XCTUnwrap(provider.requests.first)
        XCTAssertEqual(request.model, AnthropicAPI.defaultModel); XCTAssertEqual(request.effort, "high")
        XCTAssertTrue(request.instructions.contains("mission from Aster's main window"))
        XCTAssertFalse(request.tools.contains { $0["name"] as? String == "aster_mission" }, "A mission does not start more missions")
        XCTAssertEqual(request.attachments.map(\.name), ["notas.txt"]); XCTAssertTrue(store.attachments.isEmpty)
        XCTAssertEqual(AnthropicAPI.content(for: request.attachments[0])["text"] as? String, "Attached file notas.txt:\nPúblico: estudiantes")
    }
}
