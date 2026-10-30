import AppKit
import Combine

@MainActor final class ComputerController: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var paused = false
    @Published private(set) var phase = "Listo para ayudarte"
    @Published private(set) var steps: [ComputerStep] = []
    @Published private(set) var result = ""
    @Published private(set) var error = ""
    @Published private(set) var question = ""
    @Published private(set) var taskText = ""
    @Published private(set) var screenAllowed = false
    @Published private(set) var controlAllowed = false
    /// A sensitive step waiting for the user's yes or no.
    @Published private(set) var confirmation: PendingConfirmation?
    /// The task was started or resumed from the iPhone: nobody is at the Mac to confirm, so sensitive steps are declined.
    var remoteSession = false
    private var decision: Bool?
    private var waiters: [CheckedContinuation<ComputerRun, Never>] = []
    @Published var selectedDisplay = CGMainDisplayID()
    let preview = ScreenPreview()
    lazy var desktop = MacDesktop(preview: preview)
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    var onNarration: ((String) -> Void)?
    var onFinished: ((ComputerRun) -> Void)?
    private var job: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var escapeMonitor: Any?
    private var generation = UUID()
    private var reply = ""
    private var runningAgentID = "study"
    init() { refreshPermissions() }
    func refreshPermissions() {
        let screen = MacDesktop.canSee; let control = MacDesktop.canControl
        if screenAllowed != screen { screenAllowed = screen }
        if controlAllowed != control { controlAllowed = control }
    }
    func requestScreen() { MacDesktop.requestScreen(); refreshPermissions() }
    func requestControl() { MacDesktop.requestControl(); refreshPermissions() }
    func showPreview() {
        refreshPermissions(); guard screenAllowed else { error = "Permite la grabación de pantalla para ver el Mac en directo."; return }
        Task { do { try await desktop.start(displayID: selectedDisplay); error = "" } catch { self.error = error.localizedDescription } }
    }
    func hidePreview() { guard !active else { return }; Task { await desktop.stop() } }
    func start(_ text: String, agent: Specialist, settings: IntelligenceSettings, api: AgentAPI? = nil, backend: DesktopBackend? = nil, needsPermissions: Bool = true, remote: Bool = false) {
        let task = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !active, !task.isEmpty else { return }; refreshPermissions()
        if needsPermissions && (!screenAllowed || !controlAllowed) { error = "Activa Pantalla y Accesibilidad antes de empezar. Los botones de abajo abren esos permisos."; return }
        remoteSession = remote; confirmation = nil; decision = nil
        active = true; paused = false; phase = "Preparando la pantalla"; steps = []; result = ""; error = ""; question = ""; taskText = task; reply = ""; runningAgentID = agent.id
        let token = UUID(); generation = token; onBegin?()
        if needsPermissions {
            escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
                guard event.cgEvent?.getIntegerValueField(.eventSourceUserData) != 0x4153544552 else { return }
                Task { @MainActor in if event.type == .keyDown && event.keyCode == 53 { self?.stop() } else if self?.active == true && self?.paused == false { self?.pause() } }
            }
        }
        deadline = Task { [weak self] in try? await Task.sleep(for: .seconds(Double(settings.maxMinutes) * 60)); guard !Task.isCancelled, self?.generation == token else { return }; self?.stop(reason: "Se ha alcanzado el tiempo máximo de la tarea.") }
        job = Task { [weak self] in
            guard let self else { return }
            do {
                let language = settings.responseLanguage == "auto" ? (UserDefaults.standard.string(forKey: "AsterLanguage") ?? "es") : settings.responseLanguage
                let instructions = ComputerPrompt.instructions(agent: agent, language: language)
                let planner: DesktopPlanner = settings.usesClaude && api == nil
                    ? ClaudeDesktopPlanner(api: try AnthropicAPI(), model: settings.workModel, effort: settings.effort, instructions: instructions, task: task)
                    : OpenAIDesktopPlanner(api: try api ?? AgentAPI(), settings: settings, instructions: instructions, task: task)
                let engine = backend ?? self.desktop
                if backend == nil { try await self.desktop.start(displayID: self.selectedDisplay) }
                try await self.loop(planner: planner, backend: engine, token: token)
                guard self.generation == token else { return }
                self.finish(agentID: agent.id, status: self.error.isEmpty ? "Completada" : "Necesita revisión")
            } catch is CancellationError { }
            catch { guard self.generation == token else { return }; self.error = error.localizedDescription; self.phase = "Necesita revisión"; self.finish(agentID: agent.id, status: "Necesita revisión") }
        }
    }
    private func ready(_ token: UUID) async throws {
        while paused { try Task.checkCancellation(); guard generation == token, active else { throw CancellationError() }; try await Task.sleep(for: .milliseconds(150)) }
        try Task.checkCancellation(); guard generation == token, active else { throw CancellationError() }
    }
    private func loop(planner: DesktopPlanner, backend: DesktopBackend, token: UUID) async throws {
        for _ in 0..<60 {
            try await ready(token)
            let frame = try await backend.capture(); try await ready(token)
            phase = "Decidiendo el siguiente paso"
            let message = reply; reply = ""
            let (callID, action) = try await planner.next(frame, reply: message); try await ready(token)
            try action.validate(geometry: frame.geometry, active: active && !paused)
            phase = action.explanation
            steps.append(.init(text: action.explanation, action: action.action)); onNarration?(action.explanation)
            if action.action == "finish" { result = action.text ?? action.explanation; phase = "Tarea terminada"; return }
            if action.action == "ask_user" {
                question = action.text ?? action.reason ?? action.explanation; paused = true; phase = "Esperando tu respuesta"; onEnd?()
                try await ready(token); question = ""; onBegin?()
                planner.report(callID, "The user has responded in Aster. Read the next screenshot and user reply. Do not assume that any permission or external action has been granted.")
                continue
            }
            // Review the action against what is really on the Mac before anything is posted.
            let target = backend.inspect(action, geometry: frame.geometry)
            switch ActionPolicy.review(action, target: target) {
            case .allow: break
            case .block(let reason):
                steps.append(.init(text: reason, action: "blocked"))
                planner.report(callID, "Aster blocked this action: \(reason) Do not retry it or work around it. Leave it to the user and continue without it, or finish.")
                continue
            case .confirm(let reason):
                guard try await confirm(reason, step: action.explanation, token: token) else {
                    steps.append(.init(text: (remoteSession ? L("Necesita confirmación en el Mac") : L("No permitido")) + " · " + reason, action: "denied"))
                    planner.report(callID, "The user did not allow this step (\(reason)). Do not retry it or work around it. Continue without it if possible, or finish and say what is left for the user.")
                    continue
                }
                // Give the target app a moment to come back, then make sure the same control is still there.
                try await Task.sleep(for: .milliseconds(350)); try await ready(token)
                guard backend.inspect(action, geometry: frame.geometry).label == target.label else {
                    planner.report(callID, "The screen changed while waiting for permission, so the action was not performed. Inspect the new screenshot before acting.")
                    continue
                }
            }
            // Announce before posting any input. Pausing during narration blocks the action.
            try await ready(token)
            do {
                try await backend.perform(action, geometry: frame.geometry, allowed: { [weak self] in self?.active == true && self?.paused == false && self?.generation == token })
                planner.report(callID, "Action posted. Inspect the next fresh screenshot to verify its effect before proceeding.")
            } catch is CancellationError { throw CancellationError() }
            catch { planner.report(callID, "Action failed: " + error.localizedDescription + ". Inspect current screen. Do not claim success."); self.steps.append(.init(text: error.localizedDescription, action: "error")) }
        }
        error = "Se ha alcanzado el límite de 60 pasos. Revisa el resultado antes de continuar."; phase = "Necesita revisión"
    }
    func pause() { guard active, confirmation == nil else { return }; paused = true; phase = "En pausa"; onEnd?() }
    func resume(_ message: String = "") { guard active, paused, confirmation == nil else { return }; reply = message; question = ""; onBegin?(); paused = false; phase = "Continuando" }
    func stop(reason: String = "Tarea detenida") {
        guard active else { return }; job?.cancel(); deadline?.cancel(); generation = UUID(); active = false; paused = false; question = ""; confirmation = nil; decision = nil; phase = reason; cleanupMonitor(); onEnd?()
        report(.init(task: taskText, agentID: runningAgentID, steps: steps, result: result, status: "Detenida"))
        Task { await desktop.stop() }
    }
    private func finish(agentID: String, status: String) { active = false; paused = false; question = ""; deadline?.cancel(); cleanupMonitor(); report(.init(task: taskText, agentID: agentID, steps: steps, result: result.isEmpty ? error : result, status: status)); onEnd?(); Task { await desktop.stop() } }
    /// Pauses on a sensitive step until the user allows or declines it in Aster.
    private func confirm(_ reason: String, step: String, token: UUID) async throws -> Bool {
        if remoteSession { return false }
        decision = nil; confirmation = .init(reason: reason, step: step)
        paused = true; phase = "Necesita tu permiso"; onEnd?()
        defer { confirmation = nil; decision = nil }
        while decision == nil {
            try Task.checkCancellation(); guard generation == token, active else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(150))
        }
        let allowed = decision == true
        paused = false; phase = allowed ? "Continuando" : "Sin hacer ese paso"; onBegin?()
        return allowed
    }
    /// Runs a task to the end and returns its record; nil when it could not start (its reason is in `error`).
    func perform(_ text: String, agent: Specialist, settings: IntelligenceSettings, api: AgentAPI? = nil, backend: DesktopBackend? = nil, needsPermissions: Bool = true) async -> ComputerRun? {
        start(text, agent: agent, settings: settings, api: api, backend: backend, needsPermissions: needsPermissions)
        guard active else { return nil }
        return await withCheckedContinuation { waiters.append($0) }
    }
    private func report(_ run: ComputerRun) {
        onFinished?(run)
        let waiting = waiters; waiters = []
        for waiter in waiting { waiter.resume(returning: run) }
    }
    func approve() { if confirmation != nil { decision = true } }
    func deny() { if confirmation != nil { decision = false } }
    private func cleanupMonitor() { if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }; escapeMonitor = nil }
}

struct PendingConfirmation: Equatable {
    /// What Aster wants to do, in the user's words.
    var reason: String
    /// The model's explanation of the step.
    var step: String
}
