import AppKit
import EventKit
import UserNotifications
import CryptoKit

enum AppleMailReader {
    private static func script(_ source: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw AsterError.message("No se ha podido preparar la consulta de Mail.") }
        let result = script.executeAndReturnError(&error)
        guard error == nil else { throw AsterError.message("Mail necesita autorización. Conecta Apple Mail en Ajustes y acepta el permiso de macOS.") }
        return result
    }
    static func read(operation: String, query: String = "", messageID: String = "", limit: Int = 5) async throws -> [MailItem] {
        try await Task.detached(priority: .userInitiated) {
            if operation == "read" {
                guard let id = Int(messageID), id >= 0 else { throw AsterError.message("Identificador de correo no válido.") }
                let item = try script("""
                tell application "Mail"
                    set candidates to messages of inbox whose id is \(id)
                    if (count of candidates) is 0 then return {}
                    set m to item 1 of candidates
                    return {id of m, subject of m as text, sender of m as text, date received of m, content of m as text}
                end tell
                """)
                guard item.numberOfItems >= 5 else { return [] }
                return [MailItem(id: String(item.atIndex(1)?.int32Value ?? 0), subject: item.atIndex(2)?.stringValue ?? "", sender: item.atIndex(3)?.stringValue ?? "", received: item.atIndex(4)?.dateValue ?? .distantPast, body: String((item.atIndex(5)?.stringValue ?? "").prefix(30000)))]
            }
            let headers = try script("""
            tell application "Mail"
                return {id of messages of inbox, subject of messages of inbox, sender of messages of inbox, date received of messages of inbox}
            end tell
            """)
            guard let ids = headers.atIndex(1), let subjects = headers.atIndex(2), let senders = headers.atIndex(3), let dates = headers.atIndex(4) else { return [] }
            var messages: [MailItem] = []
            for i in 1...max(1, ids.numberOfItems) where i <= ids.numberOfItems {
                let subject = subjects.atIndex(i)?.stringValue ?? "", sender = senders.atIndex(i)?.stringValue ?? ""
                if query.isEmpty || subject.localizedCaseInsensitiveContains(query) || sender.localizedCaseInsensitiveContains(query) {
                    messages.append(.init(id: String(ids.atIndex(i)?.int32Value ?? 0), subject: subject, sender: sender, received: dates.atIndex(i)?.dateValue ?? .distantPast))
                }
            }
            let ordered = messages.sorted { $0.received > $1.received }
            if operation == "latest", let latest = ordered.first {
                return try await read(operation: "read", messageID: latest.id, limit: 1)
            }
            return Array(ordered.prefix(min(20, max(1, limit))))
        }.value
    }
}

extension AsterStore {
    func disableNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        state.preferences.notifications = false
        for index in state.alerts.indices { state.alerts[index].scheduled = false }; save()
    }
    func addAlert(text: String, date: Date, recurrence: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            do {
                var alert = ScheduledAlert(text: text, date: date, recurrence: recurrence)
                if state.preferences.notifications { try await scheduleAlert(alert); alert.scheduled = true }
                state.alerts.append(alert); save()
                if !alert.scheduled { notice = "Aviso guardado. Activa las notificaciones para que macOS lo entregue a la hora elegida." }
            } catch { notice = error.localizedDescription }
        }
    }
    func connectReminders() {
        Task {
            do { state.preferences.watchReminders = try await calendar.requestFullAccessToReminders(); remindersStatus = state.preferences.watchReminders == true ? "Conectado" : "Permiso denegado"; save(); if state.preferences.watchReminders == true { await refreshReminders() } }
            catch { remindersStatus = error.localizedDescription }
        }
    }
    func fetchReminders() async throws -> [EKReminder] {
        guard state.preferences.watchReminders == true, EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { throw AsterError.message("Conecta Recordatorios de Apple en Ajustes y permite el acceso de macOS.") }
        let predicate = calendar.predicateForReminders(in: nil)
        return await withCheckedContinuation { continuation in calendar.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) } }
    }
    func refreshReminders() async {
        do {
            let items = try await fetchReminders()
            reminders = items.map { .init(id: $0.calendarItemIdentifier, title: $0.title ?? "", notes: $0.notes ?? "", list: $0.calendar.title, completed: $0.isCompleted, due: $0.dueDateComponents.flatMap { Calendar.current.date(from: $0) }) }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            remindersStatus = "Conectado"
        } catch { remindersStatus = error.localizedDescription }
    }
    func completeReminder(_ id: String) {
        Task { do { guard let reminder = calendar.calendarItem(withIdentifier: id) as? EKReminder else { return }; reminder.isCompleted.toggle(); try calendar.save(reminder, commit: true); await refreshReminders() } catch { notice = error.localizedDescription } }
    }
    func scheduleAlert(_ alert: ScheduledAlert) async throws {
        let content = UNMutableNotificationContent(); content.title = "Aster"; content.body = alert.text; content.sound = .default
        var fields: Set<Calendar.Component> = [.hour, .minute, .second]
        if alert.recurrence == "weekly" { fields.insert(.weekday) }
        if alert.recurrence == "none" { fields.formUnion([.year, .month, .day]) }
        let components = Calendar.current.dateComponents(fields, from: alert.date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: alert.recurrence != "none")
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: alert.id.uuidString, content: content, trigger: trigger))
    }
    func activatePendingAlerts() async {
        let pending = state.alerts.filter { !$0.scheduled && ($0.date > Date() || $0.recurrence != "none") }
        for alert in pending {
            do { try await scheduleAlert(alert); if let index = state.alerts.firstIndex(where: { $0.id == alert.id }) { state.alerts[index].scheduled = true; save() } } catch { notice = error.localizedDescription }
        }
    }
    func cancelAlert(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        state.alerts.removeAll { $0.id == id }; save()
    }
    func handleTool(_ session: String, call: PendingToolCall, missionID: UUID) async throws -> String {
        if let receipt = state.toolReceipts.first(where: { $0.sessionID == session && $0.turnID == call.turnID && $0.callID == call.callID }) { return receipt.output }
        guard ["aster_mail", "aster_calendar", "aster_reminders", "aster_notify", "aster_health", "aster_computer", "aster_notes", "aster_mission"].contains(call.name) else { return try performTool(session, call: call, missionID: missionID) }
        // Reading mail, calendars, reminders or notes brings in text written by others.
        let operation = call.arguments["operation"] as? String ?? ""
        if call.name == "aster_mail" && operation != "draft" || call.name == "aster_notes" && operation != "create" || ["aster_calendar", "aster_reminders"].contains(call.name) && !["create", "complete"].contains(operation) {
            exposedConversations.insert(missionID)
        }
        var output: [String: Any] = [:]
        switch call.name {
        case "aster_health":
            guard let health = state.health else { throw AsterError.message("Importa una exportación de Apple Salud en Conexiones. Los datos de Salud no se pueden leer directamente en este Mac.") }
            output = ["imported_at": health.imported.formatted(.iso8601), "live": false, "record_count": health.recordCount, "latest_records": health.metrics.map { ["type": $0.id, "label": $0.label, "value": $0.value, "unit": $0.unit, "date": $0.date.formatted(.iso8601), "source": $0.source] }]
        case "aster_mail":
            guard state.preferences.watchMail else { throw AsterError.message("Conecta Apple Mail en Ajustes para consultar el correo. No hace falta pegarlo en el chat.") }
            if call.arguments["operation"] as? String == "draft" {
                let to = call.arguments["to"] as? [String] ?? [], cc = call.arguments["cc"] as? [String] ?? []
                let subject = call.arguments["subject"] as? String ?? "", body = call.arguments["body"] as? String ?? ""
                guard !(to.isEmpty && subject.isEmpty && body.isEmpty) else { throw AsterError.message("El borrador necesita destinatario, asunto o texto.") }
                setActivity("Preparando el borrador en Mail", for: missionID)
                try await mailDrafter(to, cc, subject, body)
                output = ["draft_opened": true, "sent": false, "to": to, "cc": cc, "subject": subject, "note": "The draft is open in Mail for the user to review and send."]
                break
            }
            setActivity("Leyendo Apple Mail", for: missionID)
            let items = try await AppleMailReader.read(operation: call.arguments["operation"] as? String ?? "latest", query: call.arguments["query"] as? String ?? "", messageID: call.arguments["message_id"] as? String ?? "", limit: call.arguments["limit"] as? Int ?? 5)
            output["messages"] = items.map { ["id": $0.id, "subject": $0.subject, "sender": $0.sender, "received": $0.received.formatted(.iso8601), "body": $0.body ?? ""] }
            output["source"] = "Apple Mail · inbox · live"; mailStatus = "Conectado"
        case "aster_calendar":
            guard state.preferences.watchCalendar, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw AsterError.message("Conecta Calendarios de macOS en Ajustes y permite el acceso.") }
            if call.arguments["operation"] as? String == "create" {
                guard let title = call.arguments["title"] as? String, !title.isEmpty, let start = (call.arguments["start"] as? String).flatMap(Self.parseDate) else {
                    throw AsterError.message("El evento necesita un título y una fecha de inicio ISO 8601 con zona horaria.")
                }
                let end = (call.arguments["end"] as? String).flatMap(Self.parseDate) ?? start.addingTimeInterval(3600)
                guard end > start else { throw AsterError.message("El evento debe terminar después de empezar.") }
                guard let target = calendar.defaultCalendarForNewEvents else { throw AsterError.message("No hay un calendario disponible para nuevos eventos.") }
                // The tool identity makes a repeated call update the same event instead of duplicating it.
                let token = URL(string: "aster://event/" + Self.toolIdentity(session, call: call))!
                let window = calendar.predicateForEvents(withStart: start.addingTimeInterval(-86400 * 7), end: end.addingTimeInterval(86400 * 7), calendars: nil)
                let event = calendar.events(matching: window).first { $0.url == token } ?? EKEvent(eventStore: calendar)
                event.title = String(title.prefix(300)); event.startDate = start; event.endDate = end; event.url = token
                event.location = call.arguments["location"] as? String; event.notes = call.arguments["notes"] as? String
                if event.calendar == nil { event.calendar = target }
                try calendar.save(event, span: .thisEvent, commit: true)
                output = ["created": true, "title": event.title ?? "", "start": start.formatted(.iso8601), "end": end.formatted(.iso8601), "calendar": event.calendar.title, "invitations_sent": false]
                break
            }
            let days = min(30, max(1, call.arguments["days"] as? Int ?? 1)), start = Date()
            let predicate = calendar.predicateForEvents(withStart: start, end: start.addingTimeInterval(Double(days) * 86400), calendars: nil)
            output["events"] = calendar.events(matching: predicate).sorted { $0.startDate < $1.startDate }.prefix(100).map { ["title": $0.title ?? "", "start": $0.startDate.formatted(.iso8601), "end": $0.endDate.formatted(.iso8601), "calendar": $0.calendar.title, "location": $0.location ?? ""] }
        case "aster_reminders":
            let operation = call.arguments["operation"] as? String ?? "list"
            if operation == "create" {
                guard state.preferences.watchReminders == true, EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { throw AsterError.message("Conecta Recordatorios de Apple en Ajustes.") }
                guard let title = call.arguments["title"] as? String, !title.isEmpty, let list = calendar.defaultCalendarForNewReminders() else { throw AsterError.message("Hace falta un título y una lista de Recordatorios disponible.") }
                let token = URL(string: "aster://reminder/" + Self.toolIdentity(session, call: call))!
                let existing = try await fetchReminders().first { $0.url == token }
                let reminder = existing ?? EKReminder(eventStore: calendar); reminder.title = String(title.prefix(600)); reminder.notes = call.arguments["notes"] as? String ?? ""; reminder.calendar = list; reminder.url = token
                if let value = call.arguments["due"] as? String, !value.isEmpty { guard let due = Self.parseDate(value) else { throw AsterError.message("La fecha del recordatorio no es válida.") }; reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due) }
                try calendar.save(reminder, commit: true); output = ["created": true, "id": reminder.calendarItemIdentifier, "title": reminder.title ?? ""]
            } else if operation == "complete" {
                _ = try await fetchReminders()
                guard let id = call.arguments["id"] as? String, let reminder = calendar.calendarItem(withIdentifier: id) as? EKReminder else { throw AsterError.message("No se encuentra ese recordatorio.") }
                reminder.isCompleted = true; try calendar.save(reminder, commit: true); output = ["completed": true, "id": id]
            } else {
                let items = try await fetchReminders(); let query = call.arguments["query"] as? String ?? ""
                output["reminders"] = items.filter { !$0.isCompleted && (query.isEmpty || ($0.title ?? "").localizedCaseInsensitiveContains(query)) }.prefix(100).map { ["id": $0.calendarItemIdentifier, "title": $0.title ?? "", "notes": $0.notes ?? "", "list": $0.calendar.title, "due": $0.dueDateComponents.flatMap { Calendar.current.date(from: $0) }?.formatted(.iso8601) ?? ""] }
            }
            await refreshReminders()
        case "aster_notes":
            guard state.preferences.watchNotes == true else { throw AsterError.message("Conecta Apple Notas en Ajustes para consultar y crear notas.") }
            switch call.arguments["operation"] as? String ?? "search" {
            case "read":
                guard let id = call.arguments["id"] as? String, !id.isEmpty else { throw AsterError.message("Indica qué nota abrir.") }
                setActivity("Leyendo Apple Notas", for: missionID)
                let note = try await AppleNotes.read(id)
                output = ["id": note.id, "title": note.title, "modified": note.modified?.formatted(.iso8601) ?? "", "text": note.text ?? ""]
            case "create":
                guard let title = call.arguments["title"] as? String, !title.isEmpty else { throw AsterError.message("La nota necesita un título.") }
                setActivity("Creando la nota", for: missionID)
                let id = try await AppleNotes.create(title: title, body: String((call.arguments["body"] as? String ?? "").prefix(50000)))
                output = ["created": true, "id": id, "title": title]
            default:
                setActivity("Buscando en Apple Notas", for: missionID)
                let notes = try await AppleNotes.search(call.arguments["query"] as? String ?? "", limit: call.arguments["limit"] as? Int ?? 10)
                output["notes"] = notes.map { ["id": $0.id, "title": $0.title, "modified": $0.modified?.formatted(.iso8601) ?? ""] }
            }
        case "aster_mission":
            let brief = (call.arguments["brief"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let kickoff = call.arguments["kickoff"] as? Bool == true
            try await approveIfExposed(missionID, action: L(kickoff ? "arrancar una startup completa" : "lanzar esta misión"), detail: kickoff ? (call.arguments["company"] as? String ?? "") : brief)
            var company: Company?
            if let name = (call.arguments["company"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                company = companies.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
                if company == nil {
                    createCompany(name: String(name.prefix(120)), goal: String((brief.isEmpty ? name : brief).prefix(600)))
                    company = companies.first { $0.name == String(name.prefix(120)) }
                }
            }
            let started: Bool
            if kickoff {
                guard let company else { throw AsterError.message("Indica el nombre de la empresa para arrancar la startup.") }
                started = launchStartup(company.id, background: true)
            } else {
                guard !brief.isEmpty else { throw AsterError.message("Describe qué debe entregar la misión.") }
                let mode = (call.arguments["mode"] as? String).flatMap { id in state.specialists.first { $0.id == id }?.id } ?? "director"
                started = run(String(brief.prefix(20000)), companyID: company?.id, fresh: true, specialistID: mode, background: true)
            }
            guard started, let mission = state.missions.first else { throw AsterError.message("Ahora hay demasiados trabajos en marcha. Inténtalo cuando termine alguno.") }
            if let index = state.missions.firstIndex(where: { $0.id == mission.id }) {
                if let title = call.arguments["title"] as? String, !title.isEmpty { state.missions[index].title = String(title.prefix(70)) }
                state.missions[index].parentChat = missionID
            }
            output = ["started": true, "mission_id": mission.id.uuidString, "mode": mission.specialistID, "company": company?.name ?? "", "kickoff": kickoff,
                      "note": "The mission runs in the background; its result and files appear in Aster's Missions and Inbox."]
        case "aster_computer":
            guard let task = (call.arguments["task"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !task.isEmpty else { throw AsterError.message("Describe la tarea que hay que hacer en el Mac.") }
            guard !computer.active else { throw AsterError.message("El Mac ya está haciendo otra tarea. Espera a que termine o detenla en Ordenador.") }
            try await approveIfExposed(missionID, action: L("hacer esta tarea en tu Mac"), detail: task)
            let mode = state.missions.first { $0.id == missionID }.flatMap { mission in state.specialists.first { $0.id == mission.specialistID } } ?? agent
            setActivity("Trabajando en tu Mac", for: missionID); computerOwner = missionID
            defer { computerOwner = nil }
            guard let run = await computerRunner(String(task.prefix(4000)), mode, settings) else {
                throw AsterError.message(computer.error.isEmpty ? "No se ha podido empezar la tarea en el Mac." : computer.error)
            }
            output = ["status": run.status, "result": run.result, "steps": run.steps.suffix(24).map(\.text),
                      "not_done": run.steps.filter { ["denied", "blocked"].contains($0.action) }.map(\.text)]
        case "aster_notify":
            guard let text = call.arguments["text"] as? String, !text.isEmpty, let value = call.arguments["date"] as? String, let date = Self.parseDate(value) else { throw AsterError.message("El aviso necesita un texto y una fecha ISO 8601 con zona horaria.") }
            let recurrence = call.arguments["recurrence"] as? String ?? "none"
            guard ["none", "daily", "weekly"].contains(recurrence), date > Date() || recurrence != "none" else { throw AsterError.message("La fecha del aviso debe estar en el futuro.") }
            let token = Self.toolIdentity(session, call: call)
            var alert = state.alerts.first { $0.toolKey == token } ?? ScheduledAlert(text: String(text.prefix(1000)), date: date, recurrence: recurrence, toolKey: token)
            if !state.alerts.contains(where: { $0.id == alert.id }) { state.alerts.append(alert); try persistToolState() }
            if state.preferences.notifications { try await scheduleAlert(alert); alert.scheduled = true; if let index = state.alerts.firstIndex(where: { $0.id == alert.id }) { state.alerts[index] = alert } }
            output = ["saved": true, "scheduled": alert.scheduled, "notification_id": alert.id.uuidString, "date": date.formatted(.iso8601), "needs_notification_permission": !alert.scheduled]
        default: break
        }
        let result = String(decoding: try JSONSerialization.data(withJSONObject: output, options: .sortedKeys), as: UTF8.self)
        state.toolReceipts.append(.init(sessionID: session, turnID: call.turnID, callID: call.callID, output: result)); try persistToolState(); return result
    }
    static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter(); if let date = formatter.date(from: value) { return date }; formatter.formatOptions.insert(.withFractionalSeconds); return formatter.date(from: value)
    }
    static func toolIdentity(_ session: String, call: PendingToolCall) -> String {
        SHA256.hash(data: Data((session + ":" + call.turnID + ":" + call.callID).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
