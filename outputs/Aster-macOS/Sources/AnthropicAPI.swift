import Foundation

/// Claude through the Anthropic Messages API. There is no official Swift SDK, so Aster speaks
/// HTTP directly. The key lives in the Keychain like the OpenAI one and never leaves this Mac
/// except in requests to Anthropic.
final class AnthropicAPI: @unchecked Sendable {
    static let version = "2026-10-21"
    static let defaultModel = "claude-opus-5-5"
    static let keyAccount = "anthropic-api-key"
    /// Models that may be declined by safety classifiers; the API retries those requests on a
    /// fallback model itself instead of stopping.
    static let fallbackModels: Set<String> = ["claude-opus-5-5", "claude-opus-5", "claude-fable-5-1", "claude-sonnet-5-5"]
    private let root: String
    private let key: String
    private let transport: URLSession
    private static let profiles = ProfileCache()

    init(apiKey: String? = nil, baseURL: String = "https://api.anthropic.com/v1", transport: URLSession = .shared) throws {
        if let apiKey { key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
        else if let stored = try CredentialVault.read(Self.keyAccount), let value = String(data: stored, encoding: .utf8), !value.isEmpty { key = value }
        else { throw AsterError.message("Conecta Claude en Ajustes → Conexiones para empezar.") }
        guard !key.isEmpty else { throw AsterError.message("Falta la clave de Claude.") }
        root = baseURL; self.transport = transport
    }

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) throws -> URLRequest {
        guard let url = URL(string: root + path) else { throw AsterError.message("Dirección de conexión no válida.") }
        var r = URLRequest(url: url); r.httpMethod = method; r.timeoutInterval = 600
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            if body["fallbacks"] != nil { r.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta") }
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return r
    }

    /// Streams a Messages request. Overload and rate limits are retried twice before any output.
    func stream(_ body: [String: Any]) async throws -> URLSession.AsyncBytes {
        var body = body; body["stream"] = true
        var r = try request("/messages", method: "POST", body: body); r.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for attempt in 0...2 {
            let (bytes, response) = try await transport.bytes(for: r)
            guard let http = response as? HTTPURLResponse else { throw AsterError.message("Claude devolvió una respuesta no válida.") }
            if (200..<300).contains(http.statusCode) { return bytes }
            var data = Data(); for try await byte in bytes { data.append(byte); if data.count > 64000 { break } }
            if attempt < 2, let delay = Self.retryDelay(http, attempt: attempt) { try await Task.sleep(for: .seconds(delay)); continue }
            throw parseError(data, status: http.statusCode)
        }
        throw AsterError.message("Claude está saturado ahora mismo. Inténtalo de nuevo en unos segundos.")
    }

    /// One complete Messages request, for single decisions such as the next step on the Mac.
    func message(_ body: [String: Any]) async throws -> [String: Any] {
        let r = try request("/messages", method: "POST", body: body)
        for attempt in 0...2 {
            let (data, response) = try await transport.data(for: r)
            guard let http = response as? HTTPURLResponse else { throw AsterError.message("Claude devolvió una respuesta no válida.") }
            if (200..<300).contains(http.statusCode) {
                guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AsterError.message("Claude devolvió una respuesta no válida.") }
                return value
            }
            if attempt < 2, let delay = Self.retryDelay(http, attempt: attempt) { try await Task.sleep(for: .seconds(delay)); continue }
            throw parseError(data, status: http.statusCode)
        }
        throw AsterError.message("Claude está saturado ahora mismo. Inténtalo de nuevo en unos segundos.")
    }

    private static func retryDelay(_ response: HTTPURLResponse, attempt: Int) -> Double? {
        guard [429, 500, 502, 503, 504, 529].contains(response.statusCode) else { return nil }
        let advised = (response.value(forHTTPHeaderField: "retry-after")).flatMap(Double.init) ?? 0
        return min(20, max(advised, pow(2, Double(attempt))))
    }

    /// The models this key can use, newest first, as the API lists them.
    func availableModels() async throws -> [String] {
        var models: [String] = []; var after: String?
        for _ in 0..<10 {
            var r = try request("/models?limit=100" + (after.map { "&after_id=" + $0 } ?? "")); r.timeoutInterval = 30
            let (data, response) = try await transport.data(for: r)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw parseError(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0) }
            let page = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            let entries = page["data"] as? [[String: Any]] ?? []
            for entry in entries { if let id = entry["id"] as? String { models.append(id); await Self.profiles.store(ModelProfile(entry), for: id) } }
            guard page["has_more"] as? Bool == true, let last = page["last_id"] as? String else { break }
            after = last
        }
        return models
    }

    /// What a model accepts: its output limit and whether it takes effort and images. Looked up
    /// once per model; when the lookup fails Aster sends only what every model accepts.
    func profile(_ model: String) async -> ModelProfile {
        if let known = await Self.profiles.value(for: model) { return known }
        guard let escaped = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), var r = try? request("/models/" + escaped) else { return ModelProfile() }
        r.timeoutInterval = 15
        guard let (data, response) = try? await transport.data(for: r), (response as? HTTPURLResponse)?.statusCode == 200,
              let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ModelProfile() }
        let profile = ModelProfile(entry); await Self.profiles.store(profile, for: model); return profile
    }

    /// The common parts of every Messages request Aster sends.
    func body(model: String, system: String, messages: [[String: Any]], effort: String?, maxTokens: Int, profile: ModelProfile) -> [String: Any] {
        var body: [String: Any] = ["model": model, "max_tokens": min(maxTokens, profile.maxTokens), "system": system, "messages": messages,
                                   // The instructions and tools repeat across tool rounds; cache them.
                                   "cache_control": ["type": "ephemeral"]]
        if let effort, profile.effort { body["output_config"] = ["effort": effort] }
        if Self.fallbackModels.contains(model) { body["fallbacks"] = "default" }
        return body
    }

    /// Asks for exactly one call of `tool` and returns its input. Forcing a tool is not accepted by
    /// current models, so the instructions ask for it and Aster checks that it happened.
    func toolInput(model: String, effort: String, system: String, content: [[String: Any]], tool: [String: Any], maxTokens: Int = 16000) async throws -> [String: Any] {
        let profile = await profile(model)
        var body = body(model: model, system: system, messages: [["role": "user", "content": content]], effort: effort, maxTokens: maxTokens, profile: profile)
        let converted = Self.tool(tool, streaming: false)
        body["tools"] = [converted]; body["tool_choice"] = ["type": "auto", "disable_parallel_tool_use": true]
        let response = try await message(body)
        let stop = response["stop_reason"] as? String
        if stop == "refusal" { throw AsterError.message(Self.refusal) }
        let blocks = Self.afterFallback(response["content"] as? [[String: Any]] ?? [])
        guard stop != "max_tokens", let call = blocks.first(where: { $0["type"] as? String == "tool_use" && $0["name"] as? String == converted["name"] as? String }),
              let input = call["input"] as? [String: Any] else {
            throw AsterError.message("Claude no devolvió una acción válida. Vuelve a intentarlo.")
        }
        return input
    }

    // MARK: Shapes shared with the chat provider

    /// Aster's tools are written in the OpenAI function shape; Claude takes name, description and input_schema.
    static func tool(_ function: [String: Any], streaming: Bool) -> [String: Any] {
        var tool: [String: Any] = ["name": function["name"] as? String ?? "tool", "description": function["description"] as? String ?? "",
                                   "input_schema": function["parameters"] as? [String: Any] ?? ["type": "object", "properties": [:]]]
        // Inputs stream as they are written; Aster parses them strictly and checks them before running.
        if streaming { tool["eager_input_streaming"] = true }
        return tool
    }
    /// Web search runs on Anthropic's side. Newer models filter results with the 2026 version.
    static func webSearch(for model: String) -> [String: Any] {
        let dynamic = ["claude-opus-5", "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6", "claude-sonnet-5", "claude-sonnet-4-6", "claude-fable-5"].contains { model.hasPrefix($0) }
        return ["type": dynamic ? "web_search_20260209" : "web_search_20250305", "name": "web_search", "max_uses": 5]
    }
    static func image(_ data: Data, mediaType: String = "image/jpeg") -> [String: Any] {
        ["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": data.base64EncodedString()]]
    }
    /// Files attached to a mission: images and PDFs go as such, text inline, anything else is named.
    static func content(for attachment: Attachment) -> [String: Any] {
        let ext = (attachment.name as NSString).pathExtension.lowercased()
        let images = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp"]
        if let type = images[ext] { return image(attachment.data, mediaType: type) }
        if ext == "pdf" { return ["type": "document", "title": attachment.name, "source": ["type": "base64", "media_type": "application/pdf", "data": attachment.data.base64EncodedString()]] }
        if let text = String(data: attachment.data, encoding: .utf8) { return ["type": "text", "text": "Attached file \(attachment.name):\n" + String(text.prefix(200_000))] }
        return ["type": "text", "text": "Attached file \(attachment.name) could not be read as text, an image or a PDF."]
    }
    /// After a mid-answer fallback, blocks written by the declined model before the switch are
    /// not sent back or acted on, except its text and complete server-tool pairs.
    static func afterFallback(_ blocks: [[String: Any]]) -> [[String: Any]] {
        guard let boundary = blocks.lastIndex(where: { $0["type"] as? String == "fallback" }) else { return blocks }
        let before = blocks[..<boundary]
        let answered = Set(before.compactMap { $0["type"] as? String != "server_tool_use" && $0["tool_use_id"] != nil ? $0["tool_use_id"] as? String : nil })
        let kept = before.filter { block in
            switch block["type"] as? String {
            case "thinking", "redacted_thinking", "tool_use": return false
            case "server_tool_use": return answered.contains(block["id"] as? String ?? "")
            default: return true
            }
        }
        return Array(kept) + blocks[(boundary + 1)...]
    }
    static let refusal = "Claude ha preferido no continuar con esta petición. Prueba a reformularla."

    func parseError(_ data: Data, status: Int) -> AsterError {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let error = object?["error"] as? [String: Any]
        let message = Self.friendlyError(error?["message"] as? String ?? "No se ha podido conectar con Claude.", type: error?["type"] as? String, status: status)
        return .message(message.replacingOccurrences(of: key, with: "[clave omitida]"))
    }
    static func friendlyError(_ message: String, type: String?, status: Int = 0) -> String {
        let lower = message.lowercased()
        if type == "billing_error" || status == 402 || lower.contains("credit balance") {
            return "La cuenta de Claude no tiene saldo suficiente. Revisa la facturación en la consola de Anthropic para que Aster pueda responder."
        }
        switch type ?? "" {
        case "authentication_error": return "La clave de Claude no es válida. Revísala en Ajustes → Conexiones."
        case "permission_error": return "Esta clave de Claude no tiene permiso para esa acción o ese modelo."
        case "not_found_error": return lower.contains("model") ? "Ese modelo de Claude no está disponible con esta clave. Elige otro en Ajustes." : message
        case "rate_limit_error": return "Claude está limitando las solicitudes de esta cuenta. Espera unos momentos y vuelve a intentarlo."
        case "overloaded_error": return "Claude está saturado ahora mismo. Inténtalo de nuevo en unos segundos."
        case "request_too_large": return "La petición es demasiado grande para Claude. Prueba con menos archivos o un texto más corto."
        default: return message
        }
    }
}

/// What Aster needs to know about a Claude model before calling it.
struct ModelProfile {
    var maxTokens = 64000
    var effort = false
    var images = true
    init() {}
    init(_ entry: [String: Any]) {
        if let limit = entry["max_tokens"] as? Int, limit > 0 { maxTokens = limit }
        let capabilities = entry["capabilities"] as? [String: Any] ?? [:]
        effort = (capabilities["effort"] as? [String: Any])?["supported"] as? Bool ?? false
        images = (capabilities["image_input"] as? [String: Any])?["supported"] as? Bool ?? true
    }
}

private actor ProfileCache {
    private var values: [String: ModelProfile] = [:]
    func value(for model: String) -> ModelProfile? { values[model] }
    func store(_ profile: ModelProfile, for model: String) { values[model] = profile }
}

/// Claude's Messages API with streaming. Each tool round sends the whole turn back, with the
/// model's own blocks unchanged, as the API requires.
final class AnthropicChatProvider: ChatProvider {
    private let api: AnthropicAPI
    private let rounds: Int
    init(api: AnthropicAPI, rounds: Int = OpenAIChatProvider.maximumToolRounds) { self.api = api; self.rounds = rounds }

    func respond(_ request: ChatTurnRequest, toolHandler: @escaping @MainActor (PendingToolCall) async throws -> String,
                 onEvent: @escaping @MainActor (ChatEvent) -> Void) async throws -> String {
        let profile = await api.profile(request.model)
        var question: [[String: Any]] = profile.images ? request.images.map { AnthropicAPI.image($0) } : []
        question += request.attachments.map(AnthropicAPI.content(for:))
        question.append(["type": "text", "text": request.input])
        var messages = Self.messages(history: request.history, question: question)
        var tools = request.tools.map { AnthropicAPI.tool($0, streaming: true) }
        if request.webSearch { tools.append(AnthropicAPI.webSearch(for: request.model)) }
        let schemas = Dictionary(request.tools.compactMap { tool in (tool["name"] as? String).map { ($0, tool["parameters"] as? [String: Any] ?? [:]) } }) { first, _ in first }
        var parts: [String: String] = [:]; var order: [String] = []
        for round in 0..<rounds {
            var body = api.body(model: request.model, system: request.instructions, messages: messages, effort: request.effort, maxTokens: 64000, profile: profile)
            if !tools.isEmpty { body["tools"] = tools }
            let bytes = try await api.stream(body)
            var frames = ServerSentEvents(); var turn = Turn(key: "claude-\(round)")
            for try await byte in bytes {
                try Task.checkCancellation()
                if let data = try frames.feed(byte) { try await turn.apply(data, parts: &parts, order: &order, onEvent: onEvent) }
            }
            try await turn.apply(frames.finish(), parts: &parts, order: &order, onEvent: onEvent)
            guard turn.finished else { throw AsterError.message("La respuesta se interrumpió antes de terminar. Puedes volver a enviar el mensaje.") }
            let answer = { order.compactMap { parts[$0] }.joined(separator: "\n\n") }
            let blocks = AnthropicAPI.afterFallback(turn.blocks)
            switch turn.stopReason {
            case "refusal": throw AsterError.message(AnthropicAPI.refusal)
            case "pause_turn":
                // Server-side search paused; sending the turn back lets it resume where it stopped.
                messages.append(["role": "assistant", "content": blocks]); continue
            case "tool_use": break
            case "max_tokens" where blocks.contains { $0["type"] as? String == "tool_use" }:
                throw AsterError.message("La respuesta se cortó mientras preparaba una acción. Vuelve a intentarlo con una petición más concreta.")
            default: return answer()
            }
            messages.append(["role": "assistant", "content": blocks])
            var results: [[String: Any]] = []
            for block in blocks where block["type"] as? String == "tool_use" {
                guard let id = block["id"] as? String, let name = block["name"] as? String else { continue }
                if let raw = turn.invalid[id] {
                    results.append(["type": "tool_result", "tool_use_id": id, "is_error": true, "content": Self.json(["INVALID_JSON": raw])]); continue
                }
                let arguments = block["input"] as? [String: Any] ?? [:]
                if let problem = Self.problem(arguments, schema: schemas[name]) {
                    results.append(["type": "tool_result", "tool_use_id": id, "is_error": true, "content": problem]); continue
                }
                await onEvent(.activity(OpenAIChatProvider.activity(for: name)))
                do {
                    let output = try await toolHandler(.init(turnID: "claude-\(round)", callID: id, name: name, arguments: arguments))
                    results.append(["type": "tool_result", "tool_use_id": id, "content": output])
                } catch is CancellationError { throw CancellationError() }
                catch { results.append(["type": "tool_result", "tool_use_id": id, "is_error": true, "content": Self.json(["error": error.localizedDescription])]) }
            }
            // Every result of one turn goes back together, in one message.
            messages.append(["role": "user", "content": results])
        }
        throw AsterError.message("La respuesta necesitó demasiados pasos. Para un trabajo largo, empieza una misión en la ventana principal.")
    }

    /// Claude's conversation starts with the user and alternates; Aster's transcript can begin with
    /// Aster speaking first or hold two turns in a row, so those are joined.
    static func messages(history: [ChatMessage], question: [[String: Any]]) -> [[String: Any]] {
        var turns: [(role: String, content: [[String: Any]])] = []
        for message in history where !message.text.isEmpty {
            let block: [String: Any] = ["type": "text", "text": message.text]
            if turns.last?.role == message.role { turns[turns.count - 1].content.append(block) } else { turns.append((message.role, [block])) }
        }
        if turns.first?.role == "assistant" { turns.insert(("user", [["type": "text", "text": "(Earlier in this conversation)"]]), at: 0) }
        if turns.last?.role == "user" { turns[turns.count - 1].content += question } else { turns.append(("user", question)) }
        return turns.map { ["role": $0.role, "content": $0.content] }
    }

    /// Checks a tool input against the top level of its schema before anything runs.
    static func problem(_ input: [String: Any], schema: [String: Any]?) -> String? {
        guard let schema else { return nil }
        let properties = schema["properties"] as? [String: Any] ?? [:]
        let missing = (schema["required"] as? [String] ?? []).filter { input[$0] == nil }
        if !missing.isEmpty { return json(["error": "Missing required fields: " + missing.joined(separator: ", ")]) }
        if schema["additionalProperties"] as? Bool == false, let extra = input.keys.first(where: { properties[$0] == nil }) { return json(["error": "Unknown field: " + extra]) }
        for (name, value) in input {
            guard let allowed = (properties[name] as? [String: Any])?["enum"] as? [String] else { continue }
            if let text = value as? String, !allowed.contains(text) { return json(["error": "\(name) must be one of: " + allowed.joined(separator: ", ")]) }
        }
        return nil
    }

    /// The state of one streamed response: its blocks, rebuilt from the events, ready to send back.
    private struct Turn {
        let key: String
        var blocks: [[String: Any]] = []
        var inputs: [Int: String] = [:]
        var invalid: [String: String] = [:]
        var stopReason: String?
        var finished = false
        mutating func apply(_ data: Data, parts: inout [String: String], order: inout [String], onEvent: @MainActor (ChatEvent) -> Void) async throws {
            guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = event["type"] as? String else { return }
            let index = event["index"] as? Int ?? 0
            switch type {
            case "content_block_start":
                guard var block = event["content_block"] as? [String: Any] else { return }
                while blocks.count <= index { blocks.append([:]) }
                let kind = block["type"] as? String
                if kind == "tool_use" || kind == "server_tool_use" { inputs[index] = ""; block["input"] = [String: Any]() }
                if kind == "server_tool_use" { await onEvent(.activity(block["name"] as? String == "web_fetch" ? "Leyendo una página web" : "Buscando en internet")) }
                if kind?.hasSuffix("_tool_result") == true { await onEvent(.external) }
                blocks[index] = block
                guard kind == "text" else { return }
                // Cited passages arrive as consecutive text blocks of one paragraph; text after a search starts a new one.
                if index > 0, blocks[index - 1]["type"] as? String != "text", parts[key]?.isEmpty == false { append("\n\n", parts: &parts, order: &order); await onEvent(.text(key, "\n\n")) }
                if let text = block["text"] as? String, !text.isEmpty { append(text, parts: &parts, order: &order); await onEvent(.text(key, text)) }
            case "content_block_delta":
                guard index < blocks.count, let delta = event["delta"] as? [String: Any] else { return }
                switch delta["type"] as? String {
                case "text_delta":
                    let text = delta["text"] as? String ?? ""
                    blocks[index]["text"] = (blocks[index]["text"] as? String ?? "") + text
                    append(text, parts: &parts, order: &order); await onEvent(.text(key, text))
                case "input_json_delta": inputs[index, default: ""] += delta["partial_json"] as? String ?? ""
                case "thinking_delta": blocks[index]["thinking"] = (blocks[index]["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
                case "signature_delta": blocks[index]["signature"] = delta["signature"] as? String ?? ""
                case "citations_delta":
                    if let citation = delta["citation"] { blocks[index]["citations"] = (blocks[index]["citations"] as? [Any] ?? []) + [citation] }
                default: break
                }
            case "content_block_stop":
                guard index < blocks.count, let raw = inputs.removeValue(forKey: index) else { return }
                // Inputs stream unvalidated: parse them strictly and never run a broken one.
                if raw.isEmpty { return }
                if let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] { blocks[index]["input"] = object }
                else if let id = blocks[index]["id"] as? String { invalid[id] = raw }
            case "message_delta":
                if let reason = (event["delta"] as? [String: Any])?["stop_reason"] as? String { stopReason = reason }
            case "message_stop": finished = true
            case "error":
                let error = event["error"] as? [String: Any] ?? event
                throw AsterError.message(AnthropicAPI.friendlyError(error["message"] as? String ?? "Claude no pudo responder.", type: error["type"] as? String))
            default: break
            }
        }
        private func append(_ text: String, parts: inout [String: String], order: inout [String]) {
            if parts[key] == nil { order.append(key) }
            parts[key, default: ""] += text
        }
    }
    private static func json(_ object: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys)) ?? Data("{}".utf8), as: UTF8.self)
    }
}
