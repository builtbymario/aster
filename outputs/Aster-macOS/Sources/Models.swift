import Foundation
import SwiftUI

struct Specialist: Identifiable, Codable {
    var id: String
    var name: String
    var role: String
    var detail: String
    var style: AvatarStyle
    var personality: String?
    static let defaults: [Specialist] = [
        .init(id: "director", name: "Aster", role: "Automático", detail: Specialist.autoDetail, style: .init(form: .pebble, tint: .lilac)),
        .init(id: "growth", name: "Milo", role: "Marketing", detail: "Posicionamiento, campañas, contenidos y crecimiento con resultados medibles.", style: .init(form: .pill, tint: .peach)),
        .init(id: "builder", name: "Nova", role: "Desarrollo", detail: "Webs, productos y código. Construye, verifica y explica sus decisiones.", style: .init(form: .orbit, tint: .mint)),
        .init(id: "strategy", name: "Sage", role: "Negocio", detail: "Planes de negocio, investigación y escenarios con supuestos explícitos.", style: .init(form: .pebble, tint: .pearl)),
        .init(id: "personal", name: "Lumi", role: "Personal", detail: "Te ayuda a pensar, crear y cuidar de tu agenda y tus prioridades.", style: .init(form: .pill, tint: .ink)),
        .init(id: "study", name: "Atlas", role: "Aprendizaje", detail: "Aprende contigo, explica paso a paso y te ayuda con documentos, Excel y tareas en tu Mac.", style: .init(form: .orbit, tint: .pearl)),
        .init(id: "research", name: "Aster", role: "Investigación", detail: "Investiga con fuentes verificables, compara opciones y separa los datos de las estimaciones.", style: .init()),
        .init(id: "finance", name: "Aster", role: "Finanzas", detail: "Modelos financieros, costes, precios, métricas y escenarios con supuestos explícitos.", style: .init()),
        .init(id: "content", name: "Aster", role: "Contenido", detail: "Escribe contenido con tu voz: posts, guiones, newsletters, presentaciones y textos de producto.", style: .init())
    ]
}
extension Specialist {
    /// Aster is one companion; each specialist is a mode with its own conversation, voice and personality.
    var mode: String {
        switch id {
        case "director": return "Auto"
        case "growth": return "Growth"
        case "builder": return "Builder"
        case "strategy": return "Founder"
        case "personal": return "Personal"
        case "study": return "Study"
        case "research": return "Research"
        case "finance": return "Finance"
        case "content": return "Content"
        default: return role
        }
    }
    var symbol: String {
        switch id {
        case "growth": return "chart.line.uptrend.xyaxis"
        case "builder": return "chevron.left.forwardslash.chevron.right"
        case "strategy": return "briefcase"
        case "personal": return "heart"
        case "study": return "graduationcap"
        case "research": return "magnifyingglass"
        case "finance": return "chart.pie"
        case "content": return "square.and.pencil"
        default: return "sparkle"
        }
    }
    /// "Aster · Builder", or "Aster" for the general mode.
    var title: String { id == "director" ? "Aster" : "Aster · " + mode }
    static let autoDetail = "Elige el modo adecuado para cada petición, cambia cuando hace falta y te propone los siguientes pasos."
    /// Modes in the order the interface shows them.
    static let modeOrder = ["director", "study", "builder", "strategy", "research", "finance", "growth", "content", "personal"]
}
/// A project: a company, a degree, a channel or anything else the user is working towards. It
/// keeps the stored name `Company` so workspaces saved before projects existed still load.
struct Company: Identifiable, Codable {
    var id = UUID()
    var name: String
    var goal: String
    var notes: String = ""
    var archived: Bool?
    /// The template it was created from; nil for companies made before projects, which are startups.
    var kind: String?
    /// The modes that work on this project; nil uses the template's team.
    var modes: [String]?
    /// The project's own conversation with Aster.
    var chatID: UUID?
    var template: ProjectTemplate { ProjectTemplate.all.first { $0.id == kind } ?? ProjectTemplate.all[0] }
    var team: [String] { (modes ?? template.modes).filter { Specialist.modeOrder.contains($0) && $0 != "director" } }
}

/// A starting point for a project: who works on it and the first things worth asking.
struct ProjectTemplate: Identifiable, Equatable {
    struct Action: Equatable { var title: String; var symbol: String; var prompt: String; var kickoff = false }
    var id: String
    var name: String
    var symbol: String
    var detail: String
    var goalHint: String
    var modes: [String]
    var actions: [Action]
    static let all: [ProjectTemplate] = [
        .init(id: "startup", name: "Empresa o startup", symbol: "building.2", detail: "De la idea al lanzamiento: estrategia, producto, growth y finanzas.", goalHint: "Una app de apuntes compartidos para estudiantes universitarios",
              modes: ["strategy", "research", "builder", "growth", "finance", "content"],
              actions: [.init(title: "Lanzar startup", symbol: "paperplane", prompt: "", kickoff: true),
                        .init(title: "Plan de negocio", symbol: "doc.text", prompt: "Prepara un plan de negocio útil: propuesta de valor, mercado, riesgos, costes, supuestos y próximos pasos."),
                        .init(title: "Marketing", symbol: "megaphone", prompt: "Prepara una estrategia de marketing y un primer calendario de contenidos con objetivos medibles."),
                        .init(title: "Web y producto", symbol: "hammer", prompt: "Diseña la primera versión del producto y su web: funciones clave, páginas y el texto de la portada. No publiques nada.")]),
        .init(id: "study", name: "Estudios", symbol: "graduationcap", detail: "Una carrera, una asignatura o un examen: plan, explicaciones y práctica.", goalHint: "Aprobar Cálculo II y Física de primero de Ingeniería Industrial",
              modes: ["study", "builder", "research"],
              actions: [.init(title: "Plan de estudio", symbol: "calendar", prompt: "Prepara un plan de estudio semanal para este proyecto: objetivos, temas por día, repasos y cómo comprobar que avanzo."),
                        .init(title: "Ejercicios", symbol: "pencil.and.list.clipboard", prompt: "Hazme ejercicios de práctica del tema que toca, de menos a más difícil, y corrígemelos cuando te responda."),
                        .init(title: "Explícamelo", symbol: "lightbulb", prompt: "Explícame paso a paso el concepto que más me está costando de este proyecto, con un ejemplo resuelto."),
                        .init(title: "Examen de prueba", symbol: "checklist", prompt: "Hazme un examen de prueba realista de este proyecto con su solución al final.")]),
        .init(id: "content", name: "Contenido y marca", symbol: "megaphone", detail: "Un canal, una newsletter o una marca personal que crece con constancia.", goalHint: "Un canal de YouTube de divulgación tecnológica con un vídeo a la semana",
              modes: ["content", "growth", "research"],
              actions: [.init(title: "Calendario", symbol: "calendar", prompt: "Prepara un calendario de contenidos de cuatro semanas con temas, formatos, ganchos y fechas."),
                        .init(title: "Ideas", symbol: "sparkles", prompt: "Dame diez ideas de piezas para este proyecto, cada una con su gancho y por qué funcionaría con esta audiencia."),
                        .init(title: "Audiencia", symbol: "person.2", prompt: "Analiza la audiencia de este proyecto: quién es, qué busca, dónde está y cómo llegar a ella.")]),
        .init(id: "research", name: "Investigación", symbol: "magnifyingglass", detail: "Una pregunta que responder con fuentes, datos y conclusiones claras.", goalHint: "Entender el mercado europeo de baterías para bicicletas eléctricas",
              modes: ["research", "finance", "content"],
              actions: [.init(title: "Estado del arte", symbol: "books.vertical", prompt: "Investiga el estado actual de este tema con fuentes citadas y resume lo que se sabe, lo que se discute y lo que falta."),
                        .init(title: "Preguntas clave", symbol: "questionmark.bubble", prompt: "Define las preguntas clave de esta investigación y cómo responder a cada una."),
                        .init(title: "Informe", symbol: "doc.richtext", prompt: "Escribe un informe de esta investigación con resumen, hallazgos con fuentes, datos y recomendaciones.")]),
        .init(id: "personal", name: "Personal", symbol: "person.crop.circle", detail: "Tus finanzas, tu salud, un viaje o un hábito: organizado y al día.", goalHint: "Ahorrar 3.000 € este año sin dejar de viajar",
              modes: ["personal", "finance", "study"],
              actions: [.init(title: "Plan semanal", symbol: "calendar", prompt: "Organízame la semana para avanzar en este proyecto, con tiempos realistas y recordatorios."),
                        .init(title: "Presupuesto", symbol: "eurosign", prompt: "Prepara un presupuesto sencillo para este proyecto con ingresos, gastos y lo que puedo ajustar."),
                        .init(title: "Hábitos", symbol: "repeat", prompt: "Propón tres hábitos pequeños que me acerquen al objetivo de este proyecto y cómo medirlos.")]),
        .init(id: "other", name: "Otro proyecto", symbol: "folder", detail: "Cualquier otra cosa: eliges tú quién trabaja en él.", goalHint: "Organizar la boda de mi hermana en junio",
              modes: ["research", "personal", "content"],
              actions: [.init(title: "Plan", symbol: "list.bullet.clipboard", prompt: "Prepara un plan para este proyecto con fases, tareas, fechas y riesgos."),
                        .init(title: "Próximos pasos", symbol: "arrow.turn.down.right", prompt: "¿Cuáles son los tres próximos pasos más útiles para este proyecto? Proponlos concretos.")])
    ]
}
struct Message: Identifiable, Codable {
    var id = UUID()
    var role: String
    var text: String
    var date = Date()
}
struct Mission: Identifiable, Codable {
    var id = UUID()
    var title: String
    var specialistID: String
    var companyID: UUID?
    var messages: [Message] = []
    var sessionID: String?
    var turnID: String?
    var status = "Lista"
    var error: String?
    var updated = Date()
    var archived: Bool?
    var pinned: Bool?
    var configuration: String?
    var previousSessions: [String]?
    var started: Date?
    var elapsedSeconds: Double?
    var attachmentNames: [String]?
    var artifactRecords: [AgentArtifact]?
    /// "direct" for quick chats answered by a ChatProvider; nil for hosted agent sessions.
    var engine: String?
    /// The mode Aster chose for the latest answer (Auto conversations switch freely).
    var activeMode: String?
    /// Next steps Aster proposed after its latest answer.
    var suggestions: [String]?
    /// The quick chat that started this mission; Aster returns there when it finishes.
    var parentChat: UUID?
    /// What Aster learned about the user from the latest turn, shown so it can be undone.
    var learned: [String]?
}
struct InboxNote: Identifiable, Codable {
    var id = UUID()
    var title: String
    var text: String
    var date = Date()
    var read = false
    var fingerprint: String
    var missionID: UUID?
}
struct Preferences: Codable {
    var selectedAgent = "director"
    /// Set once the welcome is finished; people who connected a key before it existed skip it.
    var onboarded: Bool?
    var notifications = false
    var watchCalendar = false
    var watchMail = false
    var watchReminders: Bool?
    var voice: String?
    var voiceEngine: String?
    var agentVoices: [String: String]?
    var narrateComputer: Bool?
    var autonomous = false
    var intervalHours = 6
    var dailyLimit = 2
    var lastAutonomous: Date?
    var dayStamp = ""
    var dailyRuns = 0
    var lastWatch: Date?
    var cloudURL = ""
    var intelligence: IntelligenceSettings?
    var autonomousCompanyID: UUID?
    var quietHours: Bool?
    var quietStart: Int?
    var quietEnd: Int?
    var autonomousBrief: String?
    var parallelMissions: Int?
    /// Read the answer aloud when the question was spoken. nil means on.
    var speakReplies: Bool?
    /// ⌥Space starts and ends dictation from any app. nil means on.
    var voiceShortcut: Bool?
    /// "island" (in the notch, the default) or "floating" (a mascot on the desktop).
    var desktopStyle: String?
    var watchNotes: Bool?
}
struct IntelligenceSettings: Codable, Equatable {
    var model = "gpt-6-astra"
    var effort = "medium"
    var responseLanguage = "auto"
    var tone = "warm"
    var detail = "balanced"
    var webSearch = true
    var delegation = true
    var maxAgents = 3
    var useMemory = true
    var automaticMemory = false
    var shareSources = false
    var maxMinutes = 12
    var userName = ""
    var instructions = ""
    /// Model for the quick chat of the desktop companions; nil uses `model`.
    var quickModel: String?
    /// Aster learns durable facts about the user from their own messages. nil is on.
    var learnFromChats: Bool?
    var learns: Bool { learnFromChats != false && useMemory }
    /// "openai" or "anthropic". nil is OpenAI, as before the provider could be chosen.
    var provider: String?
    /// The Claude model for everything Aster does when the provider is Anthropic.
    var claudeModel: String?
    var usesClaude: Bool { provider == AIProvider.anthropic.rawValue }
    var providerName: String { usesClaude ? "Claude" : "OpenAI" }
    /// The model for quick conversations, and the one for missions, the Mac and the screen.
    var chatModel: String { usesClaude ? claudeModel ?? AnthropicAPI.defaultModel : quickModel ?? model }
    var workModel: String { usesClaude ? claudeModel ?? AnthropicAPI.defaultModel : model }
}
enum AIProvider: String, CaseIterable {
    case openai, anthropic
    var name: String { self == .anthropic ? "Claude" : "OpenAI" }
    var keyAccount: String { self == .anthropic ? AnthropicAPI.keyAccount : "openai-api-key" }
    var keysURL: URL { URL(string: self == .anthropic ? "https://console.anthropic.com/settings/keys" : "https://platform.openai.com/api-keys")! }
    var billingURL: URL { URL(string: self == .anthropic ? "https://console.anthropic.com/settings/billing" : "https://platform.openai.com/settings/organization/billing/")! }
    var hasKey: Bool { (try? CredentialVault.read(keyAccount)) != nil }
    /// Checks a key by listing the models it can use, newest first.
    func models(key: String) async throws -> [String] {
        self == .anthropic ? try await AnthropicAPI(apiKey: key).availableModels() : try await AgentAPI(apiKey: key).availableModels()
    }
}
struct MemoryEntry: Identifiable, Codable {
    var id = UUID()
    var text: String
    var date = Date()
    var companyID: UUID?
    /// Learned by Aster from what the user said, rather than written by the user.
    var learned: Bool?
}
struct WorkTask: Identifiable, Codable {
    var id = UUID()
    var title: String
    var companyID: UUID?
    var specialistID: String = "director"
    var done = false
    var created = Date()
    var due: Date?
    var missionID: UUID?
}
struct ToolReceipt: Codable {
    var sessionID: String
    var turnID: String
    var callID: String
    var output: String
}
struct MailItem: Codable {
    var id: String
    var subject: String
    var sender: String
    var received: Date
    var body: String?
}
struct ReminderItem: Identifiable {
    var id: String
    var title: String
    var notes: String
    var list: String
    var completed: Bool
    var due: Date?
}
struct ScheduledAlert: Identifiable, Codable {
    var id = UUID()
    var text: String
    var date: Date
    var recurrence: String = "none"
    var scheduled = false
    var toolKey: String?
}
struct HealthMetric: Identifiable, Codable {
    var id: String
    var label: String
    var value: String
    var unit: String
    var date: Date
    var source: String
}
struct HealthSnapshot: Codable {
    var imported: Date
    var filename: String
    var metrics: [HealthMetric]
    var recordCount: Int
}
struct Attachment: Identifiable {
    var id = UUID()
    var name: String
    var data: Data
    var path: String { "/workspace/inputs/" + id.uuidString + "-" + name }
    static let maximumBytes = 10 * 1024 * 1024
}
struct AgentRoutine: Identifiable, Codable {
    var id = UUID()
    var title = ""
    var instruction = ""
    var specialistID = "personal"
    var companyID: UUID?
    var enabled = false
    var cadence = "daily"
    var hour = 9
    var minute = 0
    var timeZone = TimeZone.current.identifier
    var nextRun = Date()
    var lastMissionID: UUID?
    var history: [UUID] = []
    var nextRunLabel: String {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: timeZone) ?? .current
        return formatter.string(from: nextRun)
    }
    func next(after now: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
        var match = DateComponents(); match.hour = min(23, max(0, hour)); match.minute = min(59, max(0, minute)); match.second = 0
        var candidate = calendar.nextDate(after: now, matching: match, matchingPolicy: .nextTime, repeatedTimePolicy: .first) ?? now.addingTimeInterval(86400)
        if cadence == "weekdays" {
            while calendar.isDateInWeekend(candidate) { candidate = calendar.nextDate(after: candidate, matching: match, matchingPolicy: .nextTime, repeatedTimePolicy: .first) ?? candidate.addingTimeInterval(86400) }
        }
        return candidate
    }
}
struct SavedState: Codable {
    var specialists = Specialist.defaults
    var companies: [Company] = []
    var missions: [Mission] = []
    var inbox: [InboxNote] = []
    var preferences = Preferences()
    var memories: [MemoryEntry] = []
    var tasks: [WorkTask] = []
    var toolReceipts: [ToolReceipt] = []
    var alerts: [ScheduledAlert] = []
    var computerRuns: [ComputerRun] = []
    var health: HealthSnapshot?
    var routines: [AgentRoutine] = []
    var desktopChats: [String: UUID] = [:]
    var desktopDrafts: [String: String] = [:]
    init() {}
    enum CodingKeys: String, CodingKey { case specialists, companies, missions, inbox, preferences, memories, tasks, toolReceipts, alerts, computerRuns, health, desktopChats, desktopDrafts, routines }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        specialists = try c.decodeIfPresent([Specialist].self, forKey: .specialists) ?? Specialist.defaults
        if specialists.isEmpty { specialists = Specialist.defaults }
        companies = try c.decodeIfPresent([Company].self, forKey: .companies) ?? []
        missions = try c.decodeIfPresent([Mission].self, forKey: .missions) ?? []
        inbox = try c.decodeIfPresent([InboxNote].self, forKey: .inbox) ?? []
        preferences = try c.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
        memories = try c.decodeIfPresent([MemoryEntry].self, forKey: .memories) ?? []
        tasks = try c.decodeIfPresent([WorkTask].self, forKey: .tasks) ?? []
        toolReceipts = try c.decodeIfPresent([ToolReceipt].self, forKey: .toolReceipts) ?? []
        alerts = try c.decodeIfPresent([ScheduledAlert].self, forKey: .alerts) ?? []
        computerRuns = try c.decodeIfPresent([ComputerRun].self, forKey: .computerRuns) ?? []
        health = try c.decodeIfPresent(HealthSnapshot.self, forKey: .health)
        routines = try c.decodeIfPresent([AgentRoutine].self, forKey: .routines) ?? []
        desktopChats = try c.decodeIfPresent([String: UUID].self, forKey: .desktopChats) ?? [:]
        desktopDrafts = try c.decodeIfPresent([String: String].self, forKey: .desktopDrafts) ?? [:]
    }
}
struct PendingToolCall {
    var turnID: String
    var callID: String
    var name: String
    var arguments: [String: Any]
    static func decode(_ action: [String: Any]) -> PendingToolCall? {
        guard action["type"] as? String == "function_call", let turn = action["turn_id"] as? String,
              let call = action["call_id"] as? String, let name = action["name"] as? String else { return nil }
        let arguments = action["arguments"] as? [String: Any] ?? (action["arguments"] as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? [:]
        return .init(turnID: turn, callID: call, name: name, arguments: arguments)
    }
}

enum AsterError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

enum AgentEvent {
    case session(String), turn(String), text(String, String, Bool), activity(String), actions(String, [PendingToolCall]), completed, cancelled, failure(String)
    static func decode(_ data: Data) -> AgentEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = object["type"] as? String else { return nil }
        let session = object["session"] as? [String: Any]
        let turn = object["turn"] as? [String: Any]
        if type.contains("output_text"), let subagent = object["subagent_id"], !(subagent is NSNull) { return nil }
        if type == "agent.session.created", let id = session?["id"] as? String { return .session(id) }
        if type == "agent.session.turn.started", turn?["subagent_id"] is NSNull || turn?["subagent_id"] == nil, let id = turn?["id"] as? String { return .turn(id) }
        if type == "agent.session.turn.output_text.delta", let text = object["delta"] as? String { return .text(object["item_id"] as? String ?? "output", text, false) }
        if type == "agent.session.turn.output_text.done", let text = object["text"] as? String { return .text(object["item_id"] as? String ?? "output", text, true) }
        if type == "agent.session.turn.completed", turn?["subagent_id"] is NSNull || turn?["subagent_id"] == nil { return .completed }
        if type == "agent.session.turn.cancelled", turn?["subagent_id"] is NSNull || turn?["subagent_id"] == nil { return .cancelled }
        if type == "agent.session.turn.failed", !(turn?["subagent_id"] is NSNull) && turn?["subagent_id"] != nil { return .activity("Un especialista encontró un problema") }
        if type == "error" || type == "agent.session.failed" || type == "agent.session.environment.failed" || type == "agent.session.turn.failed" {
            let error = (object["error"] as? [String: Any]) ?? (turn?["error"] as? [String: Any]) ?? (session?["error"] as? [String: Any])
            return .failure(friendlyError(error?["message"] as? String ?? "La sesión no pudo terminar.", code: error?["code"] as? String))
        }
        if type == "agent.session.requires_action", let id = session?["id"] as? String {
            let actions = session?["required_actions"] as? [[String: Any]] ?? []
            let calls = actions.compactMap(PendingToolCall.decode)
            if calls.count != actions.count || calls.isEmpty { return .failure("La sesión requiere una acción externa que necesita revisión. Puedes recuperar su estado.") }
            return .actions(id, calls)
        }
        if type.contains("web_search") { return .activity("Investigando fuentes") }
        if type.contains("command") || type.contains("shell") { return .activity("Creando y comprobando archivos") }
        if type.contains("subagent") { return .activity("El equipo está colaborando") }
        return nil
    }
    static func friendlyError(_ message: String, code: String? = nil) -> String {
        if ["usage_limit_exceeded", "insufficient_quota", "credit_balance_exhausted"].contains(code ?? "") || message.lowercased().contains("billing limit") {
            return "La cuenta de OpenAI ha alcanzado su límite de uso o facturación. Revisa el saldo y los límites para que los agentes puedan responder."
        }
        if ["invalid_api_key", "authentication_error"].contains(code ?? "") { return "La conexión de OpenAI no es válida. Comprueba la configuración local." }
        if code == "rate_limit_exceeded" { return "OpenAI está limitando las solicitudes. Espera unos momentos y recupera el estado antes de reenviar." }
        return message
    }
}

/// Splits a server-sent event stream into the data of each complete frame.
struct ServerSentEvents {
    var oversizeMessage = "La respuesta supera el tamaño esperado."
    private var dataLines: [String] = []
    private var lineBytes = Data()
    mutating func feed(_ byte: UInt8) throws -> Data? {
        if byte == 10 {
            if lineBytes.last == 13 { lineBytes.removeLast() }
            let line = String(decoding: lineBytes, as: UTF8.self); lineBytes.removeAll(keepingCapacity: true)
            return append(line)
        }
        lineBytes.append(byte)
        if lineBytes.count > 2_000_000 { throw AsterError.message(oversizeMessage) }
        return nil
    }
    mutating func append(_ line: String) -> Data? {
        if line.isEmpty { return finish() }
        if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5)); if value.hasPrefix(" ") { value.removeFirst() }
            dataLines.append(value)
        }
        return nil
    }
    mutating func finish() -> Data {
        if !lineBytes.isEmpty {
            let line = String(decoding: lineBytes, as: UTF8.self); lineBytes.removeAll()
            if line.hasPrefix("data:") { dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
        }
        defer { dataLines = [] }
        return Data(dataLines.joined(separator: "\n").utf8)
    }
}

struct SSEParser {
    private(set) var rootTurnID: String?
    private var frames = ServerSentEvents(oversizeMessage: "La respuesta supera el tamaño esperado. Recupera la sesión para consultar el resultado guardado.")
    mutating func feed(_ byte: UInt8) throws -> AgentEvent? { try frames.feed(byte).flatMap { decode($0) } }
    mutating func append(_ line: String) -> AgentEvent? { frames.append(line).flatMap { decode($0) } }
    mutating func finish() -> AgentEvent? { decode(frames.finish()) }
    private mutating func decode(_ data: Data) -> AgentEvent? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let turn = object["turn"] as? [String: Any]
            let subagent = object["subagent_id"] ?? turn?["subagent_id"]
            if subagent == nil || subagent is NSNull {
                if let id = object["turn_id"] as? String ?? turn?["id"] as? String { rootTurnID = id }
            }
        }
        return AgentEvent.decode(data)
    }
}

struct AgentArtifact: Identifiable, Codable {
    var id: String
    var path: String
    var turnID: String?
    var sessionID: String?
}
