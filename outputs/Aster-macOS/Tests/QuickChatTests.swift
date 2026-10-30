import Foundation
import XCTest
@testable import Aster

/// Serves queued server-sent event streams and records each request.
final class StreamMockProtocol: URLProtocol {
    static var responses: [(Int, String)] = []
    static var requests: [URLRequest] = []
    static var bodies: [[String: Any]] = []
    static func reset(_ responses: [(Int, String)]) { self.responses = responses; requests = []; bodies = [] }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(buffer, count: count) }
        }
        Self.requests.append(request); Self.bodies.append((try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
        let (status, text) = Self.responses.isEmpty ? (500, #"{"error":{"message":"Missing fixture"}}"#) : Self.responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": status == 200 ? "text/event-stream" : "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// A provider whose behaviour each test scripts, used to exercise the store without a network.
final class ScriptedChatProvider: ChatProvider {
    typealias Script = @MainActor (ChatTurnRequest, @escaping @MainActor (PendingToolCall) async throws -> String, @escaping @MainActor (ChatEvent) -> Void) async throws -> String
    var requests: [ChatTurnRequest] = []
    var script: Script
    init(_ script: @escaping Script) { self.script = script }
    func respond(_ request: ChatTurnRequest, toolHandler: @escaping @MainActor (PendingToolCall) async throws -> String, onEvent: @escaping @MainActor (ChatEvent) -> Void) async throws -> String {
        requests.append(request); return try await script(request, toolHandler, onEvent)
    }
}

final class QuickChatTests: XCTestCase {
    static func stream(_ events: [[String: Any]]) -> String {
        events.map { "event: \($0["type"] as! String)\ndata: " + String(decoding: try! JSONSerialization.data(withJSONObject: $0), as: UTF8.self) + "\n\n" }.joined()
    }
    static func provider() throws -> OpenAIChatProvider {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StreamMockProtocol.self]
        return OpenAIChatProvider(api: try AgentAPI(apiKey: "test-key", baseURL: "https://aster.test/v1", transport: URLSession(configuration: config)))
    }
    static func request(webSearch: Bool = true) -> ChatTurnRequest {
        var settings = IntelligenceSettings(); settings.automaticMemory = false
        return ChatTurnRequest(model: "gpt-5.4-mini", effort: QuickChat.effort, instructions: QuickChat.instructions(for: Specialist.defaults[0], settings: settings),
                               history: [.init(role: "user", text: "Hola"), .init(role: "assistant", text: "¿En qué te ayudo?")], input: "Explícame la derivada",
                               tools: AgentAPI.functionTools(settings: settings), webSearch: webSearch)
    }

    @MainActor func testStreamsTextWithHistoryAndTools() async throws {
        StreamMockProtocol.reset([(200, Self.stream([
            ["type": "response.created", "response": ["id": "resp_1", "status": "in_progress"]],
            ["type": "response.output_item.added", "item": ["type": "message", "id": "msg_1"]],
            ["type": "response.output_text.delta", "item_id": "msg_1", "delta": "La derivada "],
            ["type": "response.output_text.delta", "item_id": "msg_1", "delta": "mide el cambio ✨"],
            ["type": "response.completed", "response": ["id": "resp_1", "status": "completed"]]
        ]))])
        var deltas: [String] = []
        let answer = try await Self.provider().respond(Self.request(), toolHandler: { _ in XCTFail("No tool was requested"); return "" }, onEvent: { event in
            if case .text(let item, let delta) = event { XCTAssertEqual(item, "msg_1"); deltas.append(delta) }
        })
        XCTAssertEqual(answer, "La derivada mide el cambio ✨")
        XCTAssertEqual(deltas, ["La derivada ", "mide el cambio ✨"], "Text reaches the chat as it streams")
        let request = try XCTUnwrap(StreamMockProtocol.requests.first), body = try XCTUnwrap(StreamMockProtocol.bodies.first)
        XCTAssertEqual(request.url?.path, "/v1/responses")
        XCTAssertNil(request.value(forHTTPHeaderField: "OpenAI-Beta"), "Quick chat uses the Responses API, not the Agents beta")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(body["model"] as? String, "gpt-5.4-mini")
        XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertNil(body["previous_response_id"], "A new turn carries its transcript instead of remote state")
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.map { $0["role"] as? String }, ["user", "assistant", "user"])
        XCTAssertEqual(input.last?["content"] as? String, "Explícame la derivada")
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertTrue(tools.contains { $0["name"] as? String == "aster_mail" } && tools.contains { $0["name"] as? String == "aster_notify" }, "Local Apple tools are available")
        XCTAssertFalse(tools.contains { $0["name"] as? String == "aster_remember" }, "Memory writing stays off unless enabled")
        XCTAssertTrue(tools.filter { $0["type"] as? String == "function" }.allSatisfy { $0["strict"] as? Bool == false }, "Schemas with optional fields are sent as non-strict")
        XCTAssertTrue(tools.contains { $0["type"] as? String == "web_search" && $0["mode"] == nil }, "Responses web search uses its own tool shape")
    }

    @MainActor func testRunsLocalToolsAndContinuesTheResponse() async throws {
        StreamMockProtocol.reset([
            (200, Self.stream([
                ["type": "response.created", "response": ["id": "resp_1"]],
                ["type": "response.output_item.done", "item": ["type": "function_call", "id": "fc_1", "call_id": "call_1", "name": "aster_calendar", "arguments": #"{"days":2}"#]],
                ["type": "response.completed", "response": ["id": "resp_1", "status": "completed"]]
            ])),
            (200, Self.stream([
                ["type": "response.created", "response": ["id": "resp_2"]],
                ["type": "response.output_text.delta", "item_id": "msg_2", "delta": "Mañana tienes una cita."],
                ["type": "response.completed", "response": ["id": "resp_2", "status": "completed"]]
            ]))
        ])
        var calls: [PendingToolCall] = []; var activities: [String] = []
        let answer = try await Self.provider().respond(Self.request(webSearch: false), toolHandler: { call in calls.append(call); return #"{"events":[{"title":"Dentista"}]}"# }, onEvent: { event in
            if case .activity(let text) = event { activities.append(text) }
        })
        XCTAssertEqual(answer, "Mañana tienes una cita.")
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, "aster_calendar"); XCTAssertEqual(calls.first?.arguments["days"] as? Int, 2)
        XCTAssertEqual(calls.first?.turnID, "resp_1", "Tool receipts are keyed to the response that asked for them")
        XCTAssertEqual(activities, ["Consultando el calendario"])
        XCTAssertEqual(StreamMockProtocol.bodies.count, 2)
        let followUp = StreamMockProtocol.bodies[1]
        XCTAssertEqual(followUp["previous_response_id"] as? String, "resp_1")
        XCTAssertNotNil(followUp["instructions"], "Instructions are sent again with each continuation")
        let output = try XCTUnwrap((followUp["input"] as? [[String: Any]])?.first)
        XCTAssertEqual(output["type"] as? String, "function_call_output"); XCTAssertEqual(output["call_id"] as? String, "call_1")
        XCTAssertEqual(output["output"] as? String, #"{"events":[{"title":"Dentista"}]}"#)
        XCTAssertFalse((StreamMockProtocol.bodies[0]["tools"] as? [[String: Any]] ?? []).contains { $0["type"] as? String == "web_search" }, "Web search follows the setting")
    }

    @MainActor func testToolErrorsReachTheModelAndFailuresAreActionable() async throws {
        StreamMockProtocol.reset([
            (200, Self.stream([
                ["type": "response.created", "response": ["id": "resp_1"]],
                ["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "call_mail", "name": "aster_mail", "arguments": #"{"operation":"latest"}"#]],
                ["type": "response.completed", "response": ["id": "resp_1"]]
            ])),
            (200, Self.stream([["type": "response.failed", "response": ["id": "resp_2", "error": ["code": "insufficient_quota", "message": "Billing limit"]]]]))
        ])
        do {
            _ = try await Self.provider().respond(Self.request(), toolHandler: { _ in throw AsterError.message("Conecta Apple Mail en Ajustes.") }, onEvent: { _ in })
            XCTFail("A failed response must not report success")
        } catch { XCTAssertTrue(error.localizedDescription.contains("facturación"), error.localizedDescription) }
        let output = try XCTUnwrap((StreamMockProtocol.bodies[1]["input"] as? [[String: Any]])?.first?["output"] as? String)
        XCTAssertTrue(output.contains("Conecta Apple Mail"), "The model hears why a tool failed and can explain it")

        StreamMockProtocol.reset([(401, #"{"error":{"code":"invalid_api_key","message":"Incorrect API key"}}"#)])
        do { _ = try await Self.provider().respond(Self.request(), toolHandler: { _ in "" }, onEvent: { _ in }); XCTFail("Rejected key must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("no es válida"), error.localizedDescription); XCTAssertFalse(error.localizedDescription.contains("test-key")) }

        StreamMockProtocol.reset([(200, Self.stream([["type": "response.created", "response": ["id": "resp_3"]], ["type": "response.output_text.delta", "item_id": "m", "delta": "Medio"]]))])
        do { _ = try await Self.provider().respond(Self.request(), toolHandler: { _ in "" }, onEvent: { _ in }); XCTFail("A cut stream is not a complete answer") }
        catch { XCTAssertTrue(error.localizedDescription.contains("interrumpió"), error.localizedDescription) }
    }

    func testHistoryIsRecentAndBounded() {
        var messages = (1...30).map { Message(role: $0 % 2 == 0 ? "assistant" : "user", text: "Mensaje \($0)") }
        messages.append(.init(role: "assistant", text: ""))
        let recent = QuickChat.history(messages)
        XCTAssertEqual(recent.count, 20); XCTAssertEqual(recent.last?.text, "Mensaje 30"); XCTAssertEqual(recent.first?.text, "Mensaje 11")
        let long = QuickChat.history([.init(role: "user", text: String(repeating: "a", count: 20000)), .init(role: "assistant", text: String(repeating: "b", count: 10000))])
        XCTAssertEqual(long.map(\.role), ["assistant"], "Older messages drop once the character budget is used")
    }

    @MainActor func testDesktopCompanionsUseTheQuickChat() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aster-quick-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let provider = ScriptedChatProvider { request, tool, event in
            if request.input.hasSuffix("Apunta la propuesta") {
                _ = try await tool(.init(turnID: "resp_a", callID: "call_task", name: "aster_create_task", arguments: ["title": "Enviar la propuesta"]))
            }
            event(.text("msg", "Hecho, "))
            event(.text("msg", "ya está."))
            return "Hecho, ya está."
        }
        let store = AsterStore(directory: folder, startServices: false, apiFactory: { throw AsterError.message("Hosted sessions are not used here") }, chatFactory: { provider })
        var settings = store.settings; settings.quickModel = "gpt-5.4-mini"; store.settings = settings
        XCTAssertTrue(store.sendDesktop("Apunta la propuesta", agentID: "personal"))
        for _ in 0..<100 where store.busy { try await Task.sleep(for: .milliseconds(10)) }
        let mission = try XCTUnwrap(store.desktopMission(for: "personal"))
        XCTAssertEqual(mission.status, "Completada"); XCTAssertEqual(mission.engine, "direct"); XCTAssertNil(mission.sessionID)
        XCTAssertEqual(mission.messages.map(\.text), ["Apunta la propuesta", "Hecho, ya está."], "The streamed answer replaces the placeholder")
        XCTAssertEqual(store.state.tasks.map(\.title), ["Enviar la propuesta"], "Local tools run through the same handler as missions")
        XCTAssertEqual(store.state.toolReceipts.last?.sessionID, "direct-" + mission.id.uuidString)
        let first = try XCTUnwrap(provider.requests.first)
        XCTAssertEqual(first.model, "gpt-5.4-mini"); XCTAssertEqual(first.effort, "low"); XCTAssertTrue(first.history.isEmpty)
        XCTAssertTrue(first.instructions.contains("You are Aster") && first.instructions.contains("Personal mode") && first.input.contains("Aster application context"), "One Aster, its mode and local context travel with the turn")

        XCTAssertTrue(store.sendDesktop("¿Y mañana?", agentID: "personal"))
        for _ in 0..<100 where store.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(provider.requests.last?.history, [.init(role: "user", text: "Apunta la propuesta"), .init(role: "assistant", text: "Hecho, ya está.")], "Follow-ups carry the local transcript")
        XCTAssertEqual(store.state.tasks.count, 1)

        XCTAssertTrue(store.run("Prepara un plan", fresh: true), "The main window still starts a mission")
        for _ in 0..<100 where store.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(store.state.missions.first { $0.title == "Prepara un plan" }?.engine, "Missions keep the hosted agent environment")
        XCTAssertEqual(provider.requests.count, 2)
    }

    @MainActor func testStoppingAndQuittingDuringAQuickAnswer() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aster-quick-stop-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let provider = ScriptedChatProvider { _, _, event in
            event(.text("msg", "Empiezo"))
            try await Task.sleep(for: .seconds(30)); return "Nunca"
        }
        let store = AsterStore(directory: folder, startServices: false, apiFactory: { throw AsterError.message("Unused") }, chatFactory: { provider })
        XCTAssertTrue(store.sendDesktop("Cuéntame algo largo", agentID: "study"))
        for _ in 0..<100 where provider.requests.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(120))
        store.flushStorage()
        let interrupted = AsterStore(directory: folder, startServices: false, apiFactory: { throw AsterError.message("Unused") }, chatFactory: { provider })
        XCTAssertEqual(interrupted.desktopMission(for: "study")?.status, "Detenida", "A quick chat interrupted by quitting needs no session recovery")
        XCTAssertTrue(interrupted.sendDesktop("Otra vez", agentID: "study"), "The user can simply send again")
        interrupted.stop(missionID: interrupted.desktopMission(for: "study")?.id)
        for _ in 0..<100 where interrupted.busy { try await Task.sleep(for: .milliseconds(10)) }

        let id = try XCTUnwrap(store.desktopMission(for: "study")?.id)
        store.stop(missionID: id)
        for _ in 0..<100 where store.busy { try await Task.sleep(for: .milliseconds(10)) }
        let stopped = try XCTUnwrap(store.desktopMission(for: "study"))
        XCTAssertFalse(store.busy, "Stopping frees the slot at once, without a remote cancellation")
        XCTAssertEqual(stopped.status, "Detenida")
        XCTAssertEqual(stopped.messages.last?.text, "Empiezo", "The partial answer stays visible")
    }
}
