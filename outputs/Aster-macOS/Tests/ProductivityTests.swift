import Foundation
import XCTest
@testable import Aster

final class ProductivityTests: XCTestCase {
    func testTextIsSafelyQuotedForAppleScript() {
        XCTAssertEqual(AppleScriptText.literal("Hola"), "\"Hola\"")
        XCTAssertEqual(AppleScriptText.literal("Dijo \"sí\" \\ fin"), "\"Dijo \\\"sí\\\" \\\\ fin\"", "Quotes and backslashes cannot end the string early")
        XCTAssertEqual(AppleScriptText.literal("una\ndos"), "\"una\" & linefeed & \"dos\"")
        XCTAssertTrue(AppleScriptText.isEmail("ana@empresa.com")); XCTAssertFalse(AppleScriptText.isEmail("ana\" & do shell script \"x"))
    }

    func testDraftsOpenForReviewAndNeverSend() throws {
        let script = try MailDrafts.script(to: ["ana@empresa.com"], cc: ["leo@empresa.com"], subject: "Propuesta \"Q4\"", body: "Hola Ana,\nadjunto la propuesta.")
        XCTAssertTrue(script.contains("make new outgoing message") && script.contains("visible:true"))
        XCTAssertTrue(script.contains("address:\"ana@empresa.com\"") && script.contains("cc recipient"))
        XCTAssertTrue(script.contains("\"Propuesta \\\"Q4\\\"\""))
        XCTAssertFalse(script.lowercased().contains("send"), "The draft is left for the user to send")
        XCTAssertThrowsError(try MailDrafts.script(to: ["no es un correo"], cc: [], subject: "", body: ""))
        XCTAssertThrowsError(try MailDrafts.script(to: Array(repeating: "a@b.co", count: 21), cc: [], subject: "", body: ""))
    }

    func testNotesAreWrittenAsEscapedHTML() {
        XCTAssertEqual(AppleNotes.html(title: "Ideas <Q4>", body: "Uno & dos\n\nTres"), "<h1>Ideas &lt;Q4&gt;</h1><div>Uno &amp; dos</div><div><br></div><div>Tres</div>")
        let search = AppleNotes.searchScript("plan \"beta\"", limit: 500)
        XCTAssertTrue(search.contains("if k > 50 then set k to 50"), "Searches are bounded")
        XCTAssertTrue(search.contains("\"plan \\\"beta\\\"\""))
        XCTAssertTrue(AppleNotes.createScript(title: "Acta", body: "Puntos").contains("make new note at default folder of default account"))
    }

    @MainActor func testMailDraftsAndNotesNeedTheirConnection() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aster-productivity-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AsterStore(directory: folder, startServices: false, apiFactory: { throw AsterError.message("Unused") })
        let mission = Mission(title: "Fixture", specialistID: "personal"); store.state.missions = [mission]
        var drafts: [([String], String)] = []
        store.mailDrafter = { to, _, subject, _ in drafts.append((to, subject)) }
        let draft = PendingToolCall(turnID: "t", callID: "draft", name: "aster_mail", arguments: ["operation": "draft", "to": ["ana@empresa.com"], "subject": "Propuesta", "body": "Hola"])
        do { _ = try await store.handleTool("s", call: draft, missionID: mission.id); XCTFail("Mail must be connected") } catch {}
        XCTAssertTrue(drafts.isEmpty)
        store.state.preferences.watchMail = true
        let output = try await store.handleTool("s", call: draft, missionID: mission.id)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        XCTAssertEqual(object["sent"] as? Bool, false); XCTAssertEqual(object["draft_opened"] as? Bool, true)
        XCTAssertEqual(drafts.first?.0, ["ana@empresa.com"])
        _ = try await store.handleTool("s", call: draft, missionID: mission.id)
        XCTAssertEqual(drafts.count, 1, "A repeated call does not open a second draft")
        do { _ = try await store.handleTool("s", call: .init(turnID: "t", callID: "notes", name: "aster_notes", arguments: ["operation": "search", "query": "plan"]), missionID: mission.id); XCTFail("Notes must be connected") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Notas")) }
        do { _ = try await store.handleTool("s", call: .init(turnID: "t", callID: "event", name: "aster_calendar", arguments: ["operation": "create", "title": "Demo", "start": "2026-11-02T10:00:00+01:00"]), missionID: mission.id); XCTFail("Calendar must be connected") } catch {}
    }

    func testToolsDescribeTheNewActions() {
        let tools = AgentAPI.functionTools(settings: IntelligenceSettings())
        func operations(_ name: String) -> [String] {
            ((tools.first { $0["name"] as? String == name }?["parameters"] as? [String: Any])?["properties"] as? [String: Any]).flatMap { ($0["operation"] as? [String: Any])?["enum"] as? [String] } ?? []
        }
        XCTAssertTrue(operations("aster_mail").contains("draft"))
        XCTAssertEqual(operations("aster_calendar"), ["list", "create"])
        XCTAssertEqual(operations("aster_notes"), ["search", "read", "create"])
    }
}
