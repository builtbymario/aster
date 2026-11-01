#if DEBUG
import AppKit

/// A development check against the real provider: runs Aster's main uses end to end on a separate
/// workspace and writes what happened to selfcheck.json there. It spends a little on the user's own
/// key, so it runs only on a debug build launched with ASTER_SELFCHECK=1 and ASTER_DATA_DIR.
/// Nothing is sent, drafted or done on the Mac: those actions are replaced and only recorded.
@MainActor enum SelfCheck {
    /// Wraps the real provider to record the tools the model used and how soon it started answering.
    final class Recorder: ChatProvider, @unchecked Sendable {
        let base: ChatProvider
        var calls: [[String: Any]] = []
        var firstText: Date?
        init(base: ChatProvider) { self.base = base }
        func respond(_ request: ChatTurnRequest, toolHandler: @escaping @MainActor (PendingToolCall) async throws -> String,
                     onEvent: @escaping @MainActor (ChatEvent) -> Void) async throws -> String {
            try await base.respond(request, toolHandler: { [self] call in
                var entry: [String: Any] = ["tool": call.name, "operation": call.arguments["operation"] as? String ?? ""]
                do { let output = try await toolHandler(call); entry["output_characters"] = output.count; calls.append(entry); return output }
                catch { entry["error"] = error.localizedDescription; calls.append(entry); throw error }
            }, onEvent: { [self] event in
                if case .text = event, firstText == nil { firstText = Date() }
                onEvent(event)
            })
        }
    }

    static func run(directory: URL) async {
        var recorder: Recorder?
        let store = AsterStore(directory: directory, startServices: false, chatFactory: {
            let settings = (try? JSONDecoder().decode(SavedState.self, from: Data(contentsOf: directory.appendingPathComponent("state.json"))))?.preferences.intelligence ?? IntelligenceSettings()
            let base: ChatProvider = settings.usesClaude ? AnthropicChatProvider(api: try AnthropicAPI(), rounds: OpenAIChatProvider.maximumToolRounds) : OpenAIChatProvider(api: try AgentAPI())
            let made = Recorder(base: base); recorder = made; return made
        })
        var actions: [String] = []
        store.approver = { title, _ in actions.append("approval asked: " + title); return false }
        store.replySpeaker = { _, _ in }
        store.mailDrafter = { to, _, subject, _ in actions.append("draft: \(to.count) recipients, subject \(subject.count) characters") }
        store.computerRunner = { task, _, _ in actions.append("mac task: " + task); return nil }
        var report: [[String: Any]] = []

        func wait(_ id: UUID?, timeout: Double) async -> Bool {
            let end = Date().addingTimeInterval(timeout)
            while let id, store.isRunning(id), Date() < end { try? await Task.sleep(for: .milliseconds(100)) }
            return id.map { !store.isRunning($0) } ?? false
        }
        func record(_ name: String, timeout: Double = 150, _ start: () -> UUID?) async {
            recorder = nil; actions = []
            let began = Date()
            let id = start()
            let finished = await wait(id, timeout: timeout)
            let mission = store.state.missions.first { $0.id == id }
            let answer = mission?.messages.last { $0.role == "assistant" }?.text ?? ""
            var entry: [String: Any] = ["name": name, "started": id != nil, "finished": finished, "seconds": (Date().timeIntervalSince(began) * 10).rounded() / 10,
                                        "status": mission?.status ?? "", "error": mission?.error ?? "", "answer": String(answer.prefix(700)), "answer_characters": answer.count,
                                        "markup_leaked": answer.contains("[["), "learned": mission?.learned ?? [], "suggestions": mission?.suggestions ?? [], "mode": mission?.activeMode ?? "",
                                        "tools": recorder?.calls ?? [], "actions": actions, "files": (mission?.artifactRecords ?? []).map { URL(fileURLWithPath: $0.path).lastPathComponent }]
            if let first = recorder?.firstText { entry["first_text_seconds"] = (first.timeIntervalSince(began) * 10).rounded() / 10 }
            if !finished, let id { store.stop(missionID: id) }
            report.append(entry); write(report, to: directory)
        }
        func fresh(_ agent: String, _ text: String, screen: Bool = false) -> UUID? {
            store.newDesktopConversation(agentID: agent)
            return store.sendDesktop(text, agentID: agent, screen: screen) ? store.desktopMission(for: agent)?.id : nil
        }

        await record("chat") { fresh("director", "Hola Aster, preséntate en dos frases.") }
        await record("follow-up") { store.sendDesktop("sí", agentID: "director") ? store.desktopMission(for: "director")?.id : nil }
        await record("web") { fresh("research", "Busca en internet cuál es la última versión estable de Swift y dime la fuente.") }
        await record("learn") { fresh("study", "Para que lo sepas: preparo el examen de Estadística del 20 de noviembre y entiendo mejor con ejemplos resueltos.") }
        await record("calendar") { fresh("personal", "¿Qué tengo en el calendario hoy y mañana?") }
        await record("reminders") { fresh("personal", "¿Qué recordatorios tengo pendientes?") }
        await record("notes") { fresh("personal", "Busca en mis notas las más recientes y dime solo cuántas hay y el título de la primera.") }
        await record("mail") { fresh("personal", "¿Cuál es mi último correo? Dime solo el remitente y el asunto.") }
        await record("draft-after-mail") { store.sendDesktop("Prepárame un borrador de respuesta diciendo que lo miro mañana.", agentID: "personal") ? store.desktopMission(for: "personal")?.id : nil }
        await record("screen") { fresh("director", "¿Qué app se ve ahora en mi pantalla? Una frase.", screen: true) }
        await record("mac-task") { fresh("director", "Abre la Calculadora del Mac.") }
        let project = store.createProject(name: "Estadística (prueba)", goal: "Aprobar el examen de Estadística", kind: "study")
        await record("project") { project.flatMap { store.sendProject("Hazme un plan de estudio de 3 días.", projectID: $0.id) ? store.projectChat($0.id)?.id : nil } }
        await record("mission", timeout: 600) {
            store.run("Escribe un archivo consejos.md con 5 consejos breves para estudiar estadística.", fresh: true, specialistID: "study", background: true) ? store.state.missions.first?.id : nil
        }
        if !store.settings.usesClaude {
            let began = Date()
            do {
                let audio = try await AgentAPI().speech("Hola, soy Aster.", voice: "marin", instructions: "Warm and natural.")
                report.append(["name": "speech", "finished": true, "bytes": audio.count, "seconds": Date().timeIntervalSince(began)])
            } catch { report.append(["name": "speech", "finished": false, "error": error.localizedDescription]) }
        }
        store.flushStorage(); write(report, to: directory)
        NSApplication.shared.terminate(nil)
    }

    private static func write(_ report: [[String: Any]], to directory: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: directory.appendingPathComponent("selfcheck.json"), options: .atomic)
    }
}
#endif
