import Foundation

/// Aster's notes inside an answer: the mode it chose, `[[mode:builder]]`, and the next steps it
/// proposes, `[[next: Investiga a los competidores | Prepara el modelo financiero]]`. They ride in
/// the answer itself, so choosing a mode or proposing steps costs no extra request, and they are
/// removed from everything the user sees or hears.
enum AsterMarkup {
    struct Parsed: Equatable {
        var text: String
        var mode: String?
        var next: [String]
    }
    private static let mode = try! NSRegularExpression(pattern: #"\[\[\s*mode\s*:\s*([A-Za-z_-]+)\s*\]\]"#, options: [.caseInsensitive])
    private static let next = try! NSRegularExpression(pattern: #"\[\[\s*next\s*:\s*(.*?)\]\]"#, options: [.dotMatchesLineSeparators, .caseInsensitive])

    static func parse(_ raw: String) -> Parsed {
        let range = NSRange(raw.startIndex..., in: raw)
        let chosen = mode.firstMatch(in: raw, range: range).flatMap { Range($0.range(at: 1), in: raw) }.map { raw[$0].lowercased() }
        let steps = next.matches(in: raw, range: range).last.flatMap { Range($0.range(at: 1), in: raw) }.map { raw[$0] } ?? ""
        let options = steps.split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return Parsed(text: display(raw), mode: chosen, next: Array(options.prefix(3).map { String($0.prefix(90)) }))
    }

    /// The answer as the user should see it, also while it streams: complete notes are removed and
    /// an unfinished one at the end is held back until it closes.
    static func display(_ raw: String) -> String {
        var text = raw
        for expression in [mode, next] { text = expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "") }
        if let open = text.range(of: "[[", options: .backwards), text[open.upperBound...].range(of: "]]") == nil { text = String(text[..<open.lowerBound]) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// How the notes are explained to the model, with the modes it may choose from.
    static func instructions(modes: [Specialist], automatic: Bool) -> String {
        let catalog = modes.map { "\($0.id) (\($0.mode)): \($0.role). \($0.detail)" }.joined(separator: "\n")
        var text = """
        Answer notes, hidden from the user: start every answer with [[mode:<id>]] naming the mode whose expertise you are applying, and end it with [[next: step | step | step]] offering up to three concrete next steps the user is likely to want, each written as a short request in the user's language from their point of view (for example: Hazme ejercicios de práctica). Be proactive in every domain: after explaining, offer practice or a plan; after code, tests or deployment; after content, more pieces or a calendar; after research, decisions or deeper analysis; after organizing, reminders or events. Offer steps you can actually do with your tools. Omit [[next:...]] only for small talk, and never mention the notes.
        Modes:
        \(catalog)
        """
        if automatic {
            text += "\nYou are in Auto mode: for each request choose the mode that fits best and switch freely as the conversation moves; apply that mode's expertise in the answer. When the user accepts a proposed step (for example by answering yes), do it right away with the right tool or mode instead of asking again."
        }
        return text
    }
}
