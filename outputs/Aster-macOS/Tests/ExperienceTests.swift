import Foundation
import XCTest
@testable import Aster

/// The interface's own logic: how answers are laid out, what the palette finds, how lists are
/// grouped, and the housekeeping that can be undone.
final class ExperienceTests: XCTestCase {
    @MainActor static func store() -> AsterStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aster-experience-" + UUID().uuidString)
        return AsterStore(directory: folder, startServices: false, apiFactory: { throw AsterError.message("Unused") })
    }

    func testAnswersBecomeListsQuotesTablesAndRules() {
        let blocks = MessageBlock.parse("""
        Intro **en negrita**.

        1. Primero
        2) Segundo
          - Dentro
        - [x] Hecho
        - [ ] Pendiente

        > Una cita
        > en dos líneas

        | A | B |
        | --- | :-: |
        | 1 | 2 |

        ---
        Final
        """)
        guard blocks.count == 6 else { return XCTFail("Expected text, list, quote, table, rule and text; got \(blocks.count)") }
        if case .text = blocks[0].kind {} else { XCTFail("A paragraph stays text") }
        guard case .list = blocks[1].kind else { return XCTFail("Numbered and bulleted lines form one list") }
        XCTAssertEqual(blocks[1].items.map(\.marker), ["1.", "2.", "•", "☑", "☐"])
        XCTAssertEqual(blocks[1].items.map(\.depth), [0, 0, 1, 0, 0], "Two spaces of indent nest an item")
        XCTAssertEqual(blocks[1].items[2].text, "Dentro")
        guard case .quote = blocks[2].kind else { return XCTFail("Lines starting with > are a quote") }
        XCTAssertEqual(blocks[2].text, "Una cita\nen dos líneas")
        guard case .table = blocks[3].kind else { return XCTFail("A header and a row of dashes make a table") }
        XCTAssertEqual(blocks[3].rows, [["A", "B"], ["1", "2"]], "The row of dashes is not data")
        if case .rule = blocks[4].kind {} else { XCTFail("--- is a rule") }
        XCTAssertEqual(blocks[5].text, "Final")
    }

    func testHalfWrittenMarkupStaysReadable() {
        let streaming = MessageBlock.parse("| Semana | Objetivo |")
        XCTAssertEqual(streaming.count, 1)
        if case .text = streaming[0].kind {} else { XCTFail("A table still being written shows as text") }
        XCTAssertNil(MessageBlock.item("-"), "A lone dash is not a list item")
        XCTAssertNil(MessageBlock.item("2026. Un año"), "A year at the start of a sentence is not a numbered item")
        XCTAssertNil(MessageBlock.item("Hola - mundo"))
        let wrapped = MessageBlock.parse("- Uno\n  sigue aquí\n- Dos")
        XCTAssertEqual(wrapped.first?.items.map(\.text), ["Uno sigue aquí", "Dos"], "A wrapped line continues its item")
        let code = MessageBlock.parse("```\n- no es lista\n| ni | tabla |\n```")
        XCTAssertEqual(code.count, 1); XCTAssertEqual(code[0].text, "- no es lista\n| ni | tabla |", "Code is never reinterpreted")
    }

    func testThePaletteFindsThingsWhateverTheAccentsOrCase() {
        let commands = ["Ajustes", "Nueva misión", "Misiones", "Plan de lanzamiento"].map { PaletteCommand(id: $0, title: $0, subtitle: $0 == "Plan de lanzamiento" ? "Misión completada" : "", symbol: "circle", group: "x", run: {}) }
        XCTAssertEqual(PaletteCommand.matching(commands, query: "").map(\.id), commands.map(\.id), "No query keeps everything in order")
        XCTAssertEqual(PaletteCommand.matching(commands, query: "MISION").map(\.id), ["Misiones", "Nueva misión", "Plan de lanzamiento"], "Titles that start with the query come first; subtitles count")
        XCTAssertEqual(PaletteCommand.matching(commands, query: "plan lanz").map(\.id), ["Plan de lanzamiento"], "Every word must be there, in any order")
        XCTAssertEqual(PaletteCommand.matching(commands, query: "  ajustés ").map(\.id), ["Ajustes"])
        XCTAssertTrue(PaletteCommand.matching(commands, query: "nada parecido").isEmpty)
    }

    func testMissionsAndTasksAreGroupedByWhenTheyMatter() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 18))!
        func mission(_ title: String, hoursAgo: Double, pinned: Bool = false) -> Mission {
            var mission = Mission(title: title, specialistID: "director"); mission.updated = now.addingTimeInterval(-hoursAgo * 3600); mission.pinned = pinned ? true : nil; return mission
        }
        let groups = MissionsView.groups([mission("vieja", hoursAgo: 400), mission("hoy", hoursAgo: 2), mission("fijada", hoursAgo: 900, pinned: true), mission("ayer", hoursAgo: 20), mission("semana", hoursAgo: 80), mission("hoy antes", hoursAgo: 10)], now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.title), ["Fijadas", "Hoy", "Ayer", "Esta semana", "Anteriores"])
        XCTAssertEqual(groups[1].items.map(\.title), ["hoy", "hoy antes"], "Newest first inside a group")
        func task(_ title: String, due: Double?, done: Bool = false) -> WorkTask { WorkTask(title: title, done: done, due: due.map { now.addingTimeInterval($0 * 3600) }) }
        let tasks = TaskBoardView.groups([task("sin fecha", due: nil), task("hecha", due: -50, done: true), task("vencida", due: -30), task("esta noche", due: 3), task("jueves", due: 70), task("mañana", due: 20)], now: now, calendar: calendar)
        XCTAssertEqual(tasks.map(\.title), ["Vencidas", "Hoy", "Próximas", "Sin fecha", "Terminadas"], "A finished task is never overdue")
        XCTAssertEqual(tasks[2].items.map(\.title), ["mañana", "jueves"], "Soonest first")
    }

    @MainActor func testRemovingThingsCanBeUndone() {
        let store = Self.store()
        store.state.missions = [Mission(title: "Uno", specialistID: "director"), Mission(title: "Dos", specialistID: "study"), Mission(title: "Tres", specialistID: "builder")]
        let second = store.state.missions[1].id
        store.selectedMission = second
        store.deleteMission(second)
        XCTAssertEqual(store.state.missions.map(\.title), ["Uno", "Tres"]); XCTAssertNil(store.selectedMission, "The open conversation closes with it")
        store.toast?.undo?()
        XCTAssertEqual(store.state.missions.map(\.title), ["Uno", "Dos", "Tres"], "Undo puts it back where it was")
        store.toast?.undo?()
        XCTAssertEqual(store.state.missions.count, 3, "Undoing twice does not duplicate it")

        let kept = store.addTask("Queda")!, removed = store.addTask("Se va")!
        store.deleteTask(removed.id)
        XCTAssertEqual(store.state.tasks.map(\.id), [kept.id])
        store.toast?.undo?()
        XCTAssertEqual(Set(store.state.tasks.map(\.id)), [kept.id, removed.id])
        var edited = kept; edited.title = "  Con nuevo nombre  "; edited.due = Date(timeIntervalSince1970: 1_800_000_000); store.updateTask(edited)
        XCTAssertEqual(store.state.tasks.first { $0.id == kept.id }?.title, "Con nuevo nombre")
        edited.title = "   "; store.updateTask(edited)
        XCTAssertEqual(store.state.tasks.first { $0.id == kept.id }?.title, "Con nuevo nombre", "An empty title is not saved")
        store.toggleTask(kept.id); store.clearCompletedTasks()
        XCTAssertEqual(store.state.tasks.map(\.id), [removed.id]); store.toast?.undo?()
        XCTAssertEqual(store.state.tasks.count, 2)

        store.addNote(title: "A", text: "a", fingerprint: "a"); store.addNote(title: "B", text: "b", fingerprint: "b")
        XCTAssertEqual(store.unread, 2); store.markAllRead(); XCTAssertEqual(store.unread, 0)
        let note = store.state.inbox[0].id; store.deleteNote(note)
        XCTAssertEqual(store.state.inbox.count, 1); store.toast?.undo?(); XCTAssertEqual(store.state.inbox.first?.id, note)
    }

    @MainActor func testARunningMissionIsNotDeleted() {
        let store = Self.store()
        let mission = Mission(title: "En marcha", specialistID: "director"); store.state.missions = [mission]
        store.startWork(mission.id)
        store.deleteMission(mission.id)
        XCTAssertEqual(store.state.missions.count, 1); XCTAssertFalse(store.notice.isEmpty, "The user is told why")
        store.finishWork(mission.id)
    }

    @MainActor func testTheWeekCountsMessagesPerDay() {
        let store = Self.store()
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        var mission = Mission(title: "Semana", specialistID: "director")
        mission.messages = [.init(role: "user", text: "hoy", date: now), .init(role: "assistant", text: "hoy también", date: now.addingTimeInterval(-3600)), .init(role: "assistant", text: "", date: now),
                            .init(role: "user", text: "anteayer", date: now.addingTimeInterval(-2 * 86400)), .init(role: "user", text: "hace mucho", date: now.addingTimeInterval(-9 * 86400))]
        store.state.missions = [mission]
        let week = store.weekActivity(now: now, calendar: calendar)
        XCTAssertEqual(week.map(\.count), [0, 0, 0, 0, 1, 0, 2], "Seven days, oldest first; empty messages and older ones do not count")
        XCTAssertEqual(week.last?.day, calendar.startOfDay(for: now))
        XCTAssertEqual(store.recentMissions().map(\.title), ["Semana"])
        store.state.missions[0].archived = true
        XCTAssertTrue(store.recentMissions().isEmpty, "Archived conversations are not offered again")
    }

    @MainActor func testDroppedFilesAreAttachedWithinTheLimits() throws {
        let store = Self.store()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aster-drop-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let note = folder.appendingPathComponent("nota.txt"); try Data("hola".utf8).write(to: note)
        store.attach([folder, note])
        XCTAssertEqual(store.attachments.map(\.name), ["nota.txt"], "Folders are skipped; files are read")
        XCTAssertTrue(store.notice.isEmpty)
        store.attach([folder.appendingPathComponent("no-existe.txt")])
        XCTAssertEqual(store.attachments.count, 1); XCTAssertFalse(store.notice.isEmpty, "A file that cannot be read says so")
    }

    func testEveryAccentHasAPaletteAndEveryPageATitle() {
        XCTAssertEqual(AsterAccent(rawValue: "desconocido") ?? .aster, .aster)
        XCTAssertEqual(Set(AsterAccent.allCases.map(\.name)).count, AsterAccent.allCases.count)
        XCTAssertEqual(AsterPage.all.count, 9, "⌘1 to ⌘9 reach every page")
        XCTAssertEqual(AsterPage.title("Personajes"), "Inicio"); XCTAssertEqual(AsterPage.title("Tareas"), "Tareas")
        XCTAssertTrue(AsterPage.hasComposer("Personajes")); XCTAssertTrue(AsterPage.hasComposer("Misiones")); XCTAssertFalse(AsterPage.hasComposer("Tareas"))
    }

    func testEveryInterfaceTextHasAnEnglishTranslation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let english = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: root.appendingPathComponent("Localization/en.json")))
        // The screens rewritten for 0.7; their texts are literals passed to L, LF or a titled control.
        let files = ["Views", "HomeView", "MissionsView", "CommandPalette", "WorkspaceViews", "Design", "RichMessage", "StoreExtras"]
        let pattern = try NSRegularExpression(pattern: #"(?:\bLF?\(|title: |subtitle: |detail: |text: )"((?:[^"\\]|\\.)+)""#)
        var missing = Set<String>()
        for file in files {
            let source = try String(contentsOf: root.appendingPathComponent("Sources/\(file).swift"), encoding: .utf8)
            for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let range = Range(match.range(at: 1), in: source) else { continue }
                let key = String(source[range]).replacingOccurrences(of: "\\\"", with: "\"")
                // Interpolated strings and symbols are built in code, not translated.
                if key.contains("\\(") || !key.contains(where: \.isLetter) || english[key] != nil { continue }
                missing.insert(key)
            }
        }
        // Names and words that read the same in both languages.
        let same: Set<String> = ["Aster", "Apple", "esc", "Auto"]
        XCTAssertEqual(missing.subtracting(same).sorted(), [], "Add these to Localization/en.json")
    }
}
