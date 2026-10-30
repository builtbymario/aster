import Foundation
import XCTest
@testable import Aster

final class ProactiveTests: XCTestCase {
    func testNotesAreReadAndHidden() {
        let parsed = AsterMarkup.parse("[[mode:builder]]\nAquí tienes la web.\n\n[[next: Investiga a los competidores | Prepara el modelo financiero |  ]]")
        XCTAssertEqual(parsed.text, "Aquí tienes la web.")
        XCTAssertEqual(parsed.mode, "builder")
        XCTAssertEqual(parsed.next, ["Investiga a los competidores", "Prepara el modelo financiero"])
        XCTAssertEqual(AsterMarkup.parse("Hola").next, []); XCTAssertNil(AsterMarkup.parse("Hola").mode)
        XCTAssertEqual(AsterMarkup.parse("[[next: a | b | c | d]]").next.count, 3, "At most three steps")
        XCTAssertEqual(AsterMarkup.parse("[[ MODE : Study ]] Vamos").mode, "study")
    }

    func testStreamingNeverShowsAHalfWrittenNote() {
        XCTAssertEqual(AsterMarkup.display("[[mo"), "")
        XCTAssertEqual(AsterMarkup.display("[[mode:study]] La derivada mide"), "La derivada mide")
        XCTAssertEqual(AsterMarkup.display("[[mode:study]] Listo.\n[[next: Hazme ejer"), "Listo.")
        XCTAssertEqual(AsterMarkup.display("let grid = [[1, 2], [3, 4]]"), "let grid = [[1, 2], [3, 4]]", "Code that looks similar stays intact")
    }

    @MainActor func testAutoChoosesModesAndProposesNextSteps() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aster-auto-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let provider = ScriptedChatProvider { request, _, event in
            if request.input.hasSuffix("Hazme una web para mi startup de IA") {
                event(.text("m", "[[mode:builder]]\nEmpiezo la web en una misión.\n[[next: Investiga la idea | Analiza a la competencia]]"))
            } else { event(.text("m", "[[mode:research]] Investigando.")) }
            return ""
        }
        let store = AsterStore(directory: folder, startServices: false, apiFactory: { throw AsterError.message("Unused") }, chatFactory: { provider })
        var spoken: [String] = []; store.replySpeaker = { text, _ in spoken.append(text) }
        XCTAssertTrue(store.sendDesktop("Hazme una web para mi startup de IA", agentID: "director", spoken: true))
        for _ in 0..<100 where store.busy { try await Task.sleep(for: .milliseconds(10)) }
        var chat = try XCTUnwrap(store.desktopMission(for: "director"))
        XCTAssertEqual(chat.messages.last?.text, "Empiezo la web en una misión.", "The notes never reach the transcript")
        XCTAssertEqual(chat.activeMode, "builder")
        XCTAssertEqual(chat.suggestions, ["Investiga la idea", "Analiza a la competencia"])
        XCTAssertEqual(spoken, ["Empiezo la web en una misión."], "Nor the voice")
        let first = try XCTUnwrap(provider.requests.first)
        XCTAssertTrue(first.instructions.contains("Auto mode") && first.instructions.contains("research (Research)"), "Auto knows every mode")

        XCTAssertTrue(store.sendDesktop("Investiga la idea", agentID: "director"))
        XCTAssertNil(store.desktopMission(for: "director")?.suggestions, "Old proposals disappear while Aster works")
        for _ in 0..<100 where store.busy { try await Task.sleep(for: .milliseconds(10)) }
        chat = try XCTUnwrap(store.desktopMission(for: "director"))
        XCTAssertEqual(chat.activeMode, "research", "Auto switches mode with the request")
        XCTAssertNil(chat.suggestions)
        XCTAssertEqual(provider.requests.last?.history.last?.text, "Empiezo la web en una misión.\n[[next: Investiga la idea | Analiza a la competencia]]", "The model remembers what it offered")

        XCTAssertTrue(store.sendDesktop("Explícame integrales", agentID: "study"))
        for _ in 0..<100 where store.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(provider.requests.last?.instructions.contains("Auto mode") ?? true, "A chosen mode stays in its mode")
        XCTAssertTrue(provider.requests.last?.instructions.contains("[[next:") ?? false, "Every mode is proactive")
    }

    @MainActor func testAsterReturnsToTheChatWhenAMissionEnds() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aster-follow-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let provider = ScriptedChatProvider { request, _, event in
            event(.text("m", request.input.contains("Aster event") ? "[[mode:builder]] Tu web está lista en Misiones.[[next: Publica la web | Escribe el texto de la portada]]" : "Lanzo la misión."))
            return ""
        }
        let store = AsterStore(directory: folder, startServices: false, apiFactory: { throw AsterError.message("Unused") }, chatFactory: { provider })
        XCTAssertTrue(store.sendDesktop("Hazme una web", agentID: "director"))
        for _ in 0..<100 where store.busy { try await Task.sleep(for: .milliseconds(10)) }
        let chat = try XCTUnwrap(store.desktopMission(for: "director"))
        var mission = Mission(title: "Web de la startup", specialistID: "builder", messages: [.init(role: "user", text: "Web"), .init(role: "assistant", text: "Web creada con tres secciones.")], status: "Completada")
        mission.parentChat = chat.id; mission.artifactRecords = [AgentArtifact(id: "a", path: "/workspace/outputs/index.html", turnID: nil, sessionID: "s")]
        store.state.missions.append(mission)
        store.followUp(afterMission: mission.id)
        for _ in 0..<100 where store.busy { try await Task.sleep(for: .milliseconds(10)) }
        let event = try XCTUnwrap(provider.requests.last?.input)
        XCTAssertTrue(event.contains("Aster event, not a message from the user") && event.contains("Web de la startup") && event.contains("index.html") && event.contains("Web creada con tres secciones."))
        let updated = try XCTUnwrap(store.desktopMission(for: "director"))
        XCTAssertEqual(updated.messages.map(\.role), ["user", "assistant", "assistant"], "Aster speaks first; no message is put in the user's mouth")
        XCTAssertEqual(updated.messages.last?.text, "Tu web está lista en Misiones.")
        XCTAssertEqual(updated.suggestions, ["Publica la web", "Escribe el texto de la portada"])

        var orphan = Mission(title: "Sin chat", specialistID: "research", status: "Completada"); orphan.messages = [.init(role: "assistant", text: "x")]
        store.state.missions.append(orphan); let before = provider.requests.count
        store.followUp(afterMission: orphan.id)
        XCTAssertEqual(provider.requests.count, before, "Missions not started from a chat stay quiet")
    }

    @MainActor func testTheGeneralModeBecomesAuto() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aster-automode-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var legacy = SavedState(); legacy.specialists[0].role = "Dirección"; legacy.specialists[0].detail = "Conecta ideas"; legacy.specialists[0].personality = "Cercano"
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(legacy).write(to: folder.appendingPathComponent("state.json"))
        let director = try XCTUnwrap(AsterStore(directory: folder, startServices: false).state.specialists.first { $0.id == "director" })
        XCTAssertEqual(director.mode, "Auto"); XCTAssertEqual(director.role, "Automático"); XCTAssertEqual(director.detail, Specialist.autoDetail)
        XCTAssertEqual(director.personality, "Cercano", "Customizations survive")
    }
}
