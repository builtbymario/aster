import Foundation
import XCTest
@testable import Aster

final class ProjectTests: XCTestCase {
    @MainActor static func store(_ provider: ScriptedChatProvider) -> (AsterStore, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aster-projects-" + UUID().uuidString)
        let store = AsterStore(directory: folder, startServices: false, apiFactory: { throw AsterError.message("Unused") }, chatFactory: { provider })
        var settings = store.settings; settings.provider = "anthropic"; store.settings = settings
        return (store, folder)
    }
    @MainActor static func settle(_ store: AsterStore) async throws { for _ in 0..<100 where store.busy { try await Task.sleep(for: .milliseconds(10)) } }

    func testCompaniesFromBeforeProjectsBecomeStartupsWithTheirTeam() throws {
        let legacy = try JSONDecoder().decode(Company.self, from: Data(#"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Apuntes","goal":"Vender apuntes","notes":""}"#.utf8))
        XCTAssertEqual(legacy.template.id, "startup")
        XCTAssertEqual(legacy.team, ["strategy", "research", "builder", "growth", "finance", "content"])
        let custom = Company(name: "Ingeniería", goal: "Aprobar", kind: "study", modes: ["director", "study", "builder", "unknown"])
        XCTAssertEqual(custom.team, ["study", "builder"], "Auto is always there; unknown modes are ignored")
        XCTAssertEqual(Set(ProjectTemplate.all.map(\.id)).count, ProjectTemplate.all.count)
        for template in ProjectTemplate.all { XCTAssertTrue(template.modes.allSatisfy { Specialist.modeOrder.contains($0) && $0 != "director" }, template.id) }
    }

    @MainActor func testEveryProjectHasItsOwnConversationWithItsTeam() async throws {
        let provider = ScriptedChatProvider { _, _, event in event(.text("m", "[[mode:study]] Empecemos por las integrales.")); return "" }
        let (store, folder) = Self.store(provider); defer { try? FileManager.default.removeItem(at: folder) }
        let degree = try XCTUnwrap(store.createProject(name: "Ingeniería Industrial", goal: "Aprobar Cálculo II", kind: "study"))
        let channel = try XCTUnwrap(store.createProject(name: "Canal de ciencia", goal: "Un vídeo a la semana", kind: "content"))

        XCTAssertTrue(store.sendProject("Explícame las integrales", projectID: degree.id))
        try await Self.settle(store)
        let chat = try XCTUnwrap(store.projectChat(degree.id))
        XCTAssertEqual(chat.companyID, degree.id); XCTAssertEqual(chat.engine, "direct")
        XCTAssertEqual(chat.messages.map(\.text), ["Explícame las integrales", "Empecemos por las integrales."])
        XCTAssertEqual(chat.activeMode, "study")
        let request = try XCTUnwrap(provider.requests.last)
        XCTAssertTrue(request.instructions.contains("project \"Ingeniería Industrial\" (Estudios)") && request.instructions.contains("Auto mode"))
        XCTAssertTrue(request.instructions.contains("study (Study)") && request.instructions.contains("builder (Builder)"))
        XCTAssertFalse(request.instructions.contains("growth (Growth)"), "Only the project's team is offered")
        XCTAssertTrue(request.input.contains("Aprobar Cálculo II"), "The project's goal comes with every message")

        XCTAssertTrue(store.sendProject("Ideas para el próximo vídeo", projectID: channel.id))
        try await Self.settle(store)
        XCTAssertNotEqual(store.projectChat(channel.id)?.id, chat.id, "Each project keeps its own conversation")
        XCTAssertTrue(provider.requests.last?.instructions.contains("growth (Growth)") ?? false)
        XCTAssertNil(store.desktopMission(for: "director"), "The island's chat is separate")

        XCTAssertTrue(store.sendProject("¿Y las derivadas?", projectID: degree.id))
        try await Self.settle(store)
        XCTAssertEqual(store.projectChat(degree.id)?.messages.count, 4, "The conversation continues")
        XCTAssertEqual(provider.requests.last?.history.first?.text, "Explícame las integrales")

        store.newProjectConversation(degree.id)
        XCTAssertNil(store.projectChat(degree.id)); XCTAssertNotNil(store.state.missions.first { $0.id == chat.id }, "The old conversation stays in Missions")
    }

    @MainActor func testWorkStartedInAProjectStaysInIt() async throws {
        let provider = ScriptedChatProvider { _, _, event in event(.text("m", "Listo.")); return "" }
        let (store, folder) = Self.store(provider); defer { try? FileManager.default.removeItem(at: folder) }
        let startup = try XCTUnwrap(store.createProject(name: "Apuntes", goal: "Una app de apuntes", kind: "startup"))
        XCTAssertTrue(store.sendProject("Hola", projectID: startup.id)); try await Self.settle(store)
        let chat = try XCTUnwrap(store.projectChat(startup.id))

        _ = try await store.handleTool("s", call: .init(turnID: "t", callID: "m", name: "aster_mission", arguments: ["brief": "Plan de marketing", "mode": "growth"]), missionID: chat.id)
        let mission = try XCTUnwrap(store.state.missions.first { $0.parentChat == chat.id })
        XCTAssertEqual(mission.companyID, startup.id, "A mission without a company belongs to the chat's project")
        XCTAssertEqual(store.companies.count, 1, "No stray project is created")
        try await Self.settle(store)

        let kickoff = try XCTUnwrap(startup.template.actions.first { $0.kickoff })
        XCTAssertTrue(store.startProjectAction(kickoff, projectID: startup.id))
        let launched = try XCTUnwrap(store.state.missions.first)
        XCTAssertEqual(launched.companyID, startup.id); XCTAssertEqual(launched.parentChat, chat.id)
        XCTAssertTrue(store.projectChat(startup.id)?.messages.last?.text.contains("departamentos") ?? false, "The project's chat says what is running")
        try await Self.settle(store)
    }
}
