import Foundation

/// Builds AppleScript string expressions from arbitrary text, line breaks included.
enum AppleScriptText {
    static func literal(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            .map { "\"" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
            .joined(separator: " & linefeed & ")
    }
    static func run(_ source: String, failure: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw AsterError.message(failure) }
        let result = script.executeAndReturnError(&error)
        guard error == nil else { throw AsterError.message(failure) }
        return result
    }
    static func isEmail(_ text: String) -> Bool { text.range(of: #"^[^@\s"]+@[^@\s"]+\.[^@\s"]+$"#, options: .regularExpression) != nil }
}

/// Opens a Mail draft for the user to review. Aster never sends mail itself.
enum MailDrafts {
    static func script(to: [String], cc: [String], subject: String, body: String) throws -> String {
        let recipients = to.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let copies = cc.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard recipients.count + copies.count <= 20, (recipients + copies).allSatisfy(AppleScriptText.isEmail) else {
            throw AsterError.message("Revisa las direcciones de correo del borrador.")
        }
        let add = recipients.map { "make new to recipient at end of to recipients with properties {address:\(AppleScriptText.literal($0))}" }
            + copies.map { "make new cc recipient at end of cc recipients with properties {address:\(AppleScriptText.literal($0))}" }
        return """
        tell application "Mail"
            set draft to make new outgoing message with properties {subject:\(AppleScriptText.literal(String(subject.prefix(300)))), content:\(AppleScriptText.literal(String(body.prefix(20000)))), visible:true}
            tell draft
                \(add.joined(separator: "\n        "))
            end tell
            activate
        end tell
        """
    }
    static func open(to: [String], cc: [String], subject: String, body: String) async throws {
        let source = try script(to: to, cc: cc, subject: subject, body: body)
        try await Task.detached(priority: .userInitiated) {
            _ = try AppleScriptText.run(source, failure: "Mail necesita autorización. Conecta Apple Mail en Ajustes y acepta el permiso de macOS.")
        }.value
    }
}

struct NoteItem: Equatable {
    var id: String
    var title: String
    var modified: Date?
    var text: String?
}

/// Apple Notes through AppleScript: search, read and create notes in the default folder.
enum AppleNotes {
    static let failure = "Notas necesita autorización. Conecta Apple Notas en Ajustes y acepta el permiso de macOS."
    static func searchScript(_ query: String, limit: Int) -> String {
        let filter = query.isEmpty ? "notes" : "(notes whose name contains \(AppleScriptText.literal(query)) or plaintext contains \(AppleScriptText.literal(query)))"
        return """
        tell application "Notes"
            set found to \(filter)
            set k to count of found
            if k > \(max(1, min(50, limit))) then set k to \(max(1, min(50, limit)))
            set out to {}
            repeat with i from 1 to k
                set n to item i of found
                set end of out to {id of n, name of n, modification date of n}
            end repeat
            return out
        end tell
        """
    }
    static func createScript(title: String, body: String) -> String {
        """
        tell application "Notes"
            set n to make new note at default folder of default account with properties {body:\(AppleScriptText.literal(html(title: title, body: body)))}
            return id of n
        end tell
        """
    }
    /// Notes takes HTML; the first line becomes the note's title.
    static func html(title: String, body: String) -> String {
        func escape(_ text: String) -> String { text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        let lines = body.components(separatedBy: .newlines).map { $0.isEmpty ? "<div><br></div>" : "<div>\(escape($0))</div>" }
        return "<h1>\(escape(String(title.prefix(200))))</h1>" + lines.joined()
    }
    static func search(_ query: String, limit: Int = 10) async throws -> [NoteItem] {
        let source = searchScript(query, limit: limit)
        return try await Task.detached(priority: .userInitiated) {
            let list = try AppleScriptText.run(source, failure: failure)
            guard list.numberOfItems > 0 else { return [] }
            return (1...list.numberOfItems).compactMap { index in
                guard let row = list.atIndex(index), let id = row.atIndex(1)?.stringValue else { return nil }
                return NoteItem(id: id, title: row.atIndex(2)?.stringValue ?? "", modified: row.atIndex(3)?.dateValue)
            }
        }.value
    }
    static func read(_ id: String) async throws -> NoteItem {
        let source = """
        tell application "Notes"
            set n to note id \(AppleScriptText.literal(id))
            return {id of n, name of n, modification date of n, plaintext of n}
        end tell
        """
        return try await Task.detached(priority: .userInitiated) {
            let row = try AppleScriptText.run(source, failure: "No se encuentra esa nota.")
            return NoteItem(id: row.atIndex(1)?.stringValue ?? id, title: row.atIndex(2)?.stringValue ?? "", modified: row.atIndex(3)?.dateValue,
                            text: String((row.atIndex(4)?.stringValue ?? "").prefix(30000)))
        }.value
    }
    static func create(title: String, body: String) async throws -> String {
        let source = createScript(title: title, body: body)
        return try await Task.detached(priority: .userInitiated) {
            try AppleScriptText.run(source, failure: failure).stringValue ?? ""
        }.value
    }
}
