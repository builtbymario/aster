import Foundation
import XCTest
@testable import Aster

final class StartupTests: XCTestCase {
    @MainActor func store() -> (AsterStore, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aster-startup-" + UUID().uuidString)
        return (AsterStore(directory: folder, startServices: false, apiFactory: { throw AsterError.message("Offline fixture") }), folder)
    }

    @MainActor func testNewModesJoinExistingWorkspaces() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aster-modes-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var legacy = SavedState(); legacy.specialists = Array(Specialist.defaults.prefix(6)); legacy.specialists[1].personality = "Directo y con datos"
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(legacy).write(to: folder.appendingPathComponent("state.json"))
        let store = AsterStore(directory: folder, startServices: false)
        XCTAssertEqual(Set(store.state.specialists.map(\.id)), Set(Specialist.modeOrder), "Research, Finance and Content are added")
        XCTAssertEqual(store.state.specialists[1].personality, "Directo y con datos", "Existing modes keep their settings")
        XCTAssertEqual(Specialist.defaults.first { $0.id == "finance" }?.mode, "Finance")
    }

    @MainActor func testTheQuickChatCanKickOffAStartup() async throws {
        let (store, folder) = store(); defer { try? FileManager.default.removeItem(at: folder) }
        let chat = Mission(title: "Chat", specialistID: "director"); store.state.missions = [chat]
        let call = PendingToolCall(turnID: "t", callID: "kickoff", name: "aster_mission", arguments: ["brief": "App para que estudiantes compartan apuntes", "company": "Lumen", "kickoff": true])
        let output = try await store.handleTool("s", call: call, missionID: chat.id)
        let company = try XCTUnwrap(store.companies.first { $0.name == "Lumen" }, "A new company is created")
        XCTAssertEqual(company.goal, "App para que estudiantes compartan apuntes")
        let mission = try XCTUnwrap(store.state.missions.first { $0.companyID == company.id })
        XCTAssertEqual(mission.specialistID, "director", "The director coordinates the departments")
        let brief = try XCTUnwrap(mission.messages.first?.text)
        for deliverable in ["01-estrategia.md", "02-mercado.md", "03-producto.md", "04-growth.md", "05-finanzas.csv", "06-legal-operaciones.md", "aster_create_task"] {
            XCTAssertTrue(brief.contains(deliverable), deliverable)
        }
        XCTAssertTrue(brief.contains("No publiques, no contrates, no gastes dinero ni envíes nada"))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        XCTAssertEqual(object["started"] as? Bool, true); XCTAssertEqual(object["company"] as? String, "Lumen")
        let again = try await store.handleTool("s", call: call, missionID: chat.id)
        XCTAssertEqual(again, output); XCTAssertEqual(store.state.missions.filter { $0.companyID == company.id }.count, 1, "A repeated call starts nothing new")
        XCTAssertEqual(store.page, "Personajes", "Work started from the chat does not take over the main window")
    }

    @MainActor func testMissionsStartInTheRequestedMode() async throws {
        let (store, folder) = store(); defer { try? FileManager.default.removeItem(at: folder) }
        let chat = Mission(title: "Chat", specialistID: "director"); store.state.missions = [chat]
        _ = try await store.handleTool("s", call: .init(turnID: "t", callID: "research", name: "aster_mission", arguments: ["brief": "Compara tres CRMs para una startup", "mode": "research", "title": "CRMs"]), missionID: chat.id)
        let mission = try XCTUnwrap(store.state.missions.first { $0.title == "CRMs" })
        XCTAssertEqual(mission.specialistID, "research"); XCTAssertNil(mission.companyID)
        do { _ = try await store.handleTool("s", call: .init(turnID: "t", callID: "empty", name: "aster_mission", arguments: ["brief": " "]), missionID: chat.id); XCTFail("An empty brief starts nothing") } catch {}
        do { _ = try await store.handleTool("s", call: .init(turnID: "t", callID: "nameless", name: "aster_mission", arguments: ["brief": "x", "kickoff": true]), missionID: chat.id); XCTFail("A kickoff needs a company") } catch {}
        let modes = (QuickChat.tools(settings: IntelligenceSettings()).first { $0["name"] as? String == "aster_mission" }?["parameters"] as? [String: Any]).flatMap { (($0["properties"] as? [String: Any])?["mode"] as? [String: Any])?["enum"] as? [String] }
        XCTAssertEqual(modes, Specialist.modeOrder)
    }

    func testTheKickoffIsTranslated() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Localization/en.json")
        let english = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        XCTAssertTrue(english[AsterStore.startupBrief]?.contains("01-strategy.md") == true, "The English interface sends the English brief")
    }
}
