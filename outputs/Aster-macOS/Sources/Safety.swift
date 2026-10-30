import Foundation

// Every action the AI proposes on the Mac is reviewed here before it runs. The model is told to
// leave irreversible steps to the user, but safety does not depend on it: what sends, pays,
// deletes, publishes or grants access needs the user's yes, and some things Aster never does.

/// What is at the place an action acts on, read from the Mac rather than from the model.
struct ActionTarget: Equatable {
    /// Title, description and role of the control under the pointer.
    var label: String?
    var appName: String?
    var bundleID: String?
    /// The focused field is a password field.
    var secureField = false
    /// The focused element takes text (a form field, a search box or the address bar).
    var focusedEditable = false
}

enum ActionReview: Equatable {
    case allow
    case confirm(String)
    case block(String)
}

enum ActionPolicy {
    /// Words on a control that mean the action leaves the Mac, costs money, cannot be undone or grants access.
    static let controlWords = [
        "send", "enviar", "envia", "envio", "reenviar", "forward", "reply all", "responder a todos", "submit", "publish", "publicar", "post", "tweet",
        "pay", "pagar", "buy", "comprar", "purchase", "order", "place order", "realizar pedido", "checkout", "transfer", "transferir",
        "delete", "eliminar", "borrar", "remove", "quitar", "trash", "papelera", "empty", "vaciar", "erase", "format", "reset", "restablecer",
        "sign", "firmar", "accept", "aceptar", "agree", "acepto", "confirm", "confirmar", "subscribe", "suscribirse", "install", "instalar", "uninstall", "desinstalar",
        "share", "compartir", "invite", "invitar", "allow", "permitir", "grant", "conceder", "log out", "cerrar sesion", "sign out", "unsubscribe", "cancel subscription"
    ]
    /// Words in the model's own explanation that mean the step leaves the Mac or costs money.
    static let intentWords = [
        "send", "enviar", "envio", "reenviar", "submit", "publish", "publicar", "post", "pay", "pagar", "buy", "comprar", "purchase", "checkout",
        "transfer", "transferir", "sign", "firmar", "subscribe", "suscribir", "install", "instalar", "accept the terms", "aceptar los terminos"
    ]
    /// Apps where Return sends what was typed.
    static let messagingApps = ["com.apple.MobileSMS", "com.apple.mail", "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram", "com.tinyspeck.slackmacgap",
                                "com.hnc.Discord", "com.microsoft.teams2", "com.microsoft.Outlook", "org.whispersystems.signal-desktop", "com.facebook.archon"]
    static let browsers = ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser"]
    /// Apps Aster never operates itself.
    static let forbiddenApps = ["terminal", "iterm", "script editor", "editor de scripts", "automator", "keychain access", "acceso a llaveros", "passwords", "contrasenas", "system settings", "ajustes del sistema", "system preferences"]

    static func review(_ action: DesktopAction, target: ActionTarget) -> ActionReview {
        let app = target.appName ?? L("la app activa")
        switch action.action {
        case "type":
            let text = action.text ?? ""
            if target.secureField { return .block(L("Aster no escribe contraseñas. Introdúcela tú.")) }
            if containsSecret(text) { return .block(L("Aster no escribe números de tarjeta, claves ni contraseñas. Introdúcelos tú.")) }
            if text.contains("\n"), messagingApps.contains(target.bundleID ?? "") { return .confirm(LF("Escribir y enviar un mensaje en %@", app)) }
            if text.contains("\n"), browsers.contains(target.bundleID ?? ""), target.focusedEditable { return .confirm(LF("Enviar un formulario o abrir una dirección en %@", app)) }
        case "key":
            let key = (action.key ?? "").lowercased().replacingOccurrences(of: " ", with: "")
            let parts = Set(key.split(separator: "+").map { $0 == "command" ? "cmd" : $0 == "option" ? "alt" : $0 == "control" ? "ctrl" : String($0) })
            let main = key.split(separator: "+").last.map(String.init) ?? ""
            if parts.contains("cmd") && parts.contains("shift") && main == "q" || parts.contains("cmd") && parts.contains("ctrl") && main == "q" {
                return .block(L("Aster no cierra la sesión ni bloquea el Mac."))
            }
            if parts.contains("cmd") && ["backspace", "delete"].contains(main) { return .confirm(LF("Mover a la papelera o borrar en %@", app)) }
            if parts.contains("cmd") && main == "q" { return .confirm(LF("Cerrar %@; el trabajo sin guardar podría perderse", app)) }
            if parts.contains("cmd") && parts.contains("alt") && ["escape", "esc"].contains(main) { return .confirm(L("Forzar la salida de una app")) }
            if ["return", "enter"].contains(main) {
                let id = target.bundleID ?? ""
                if messagingApps.contains(id) { return .confirm(LF("Enviar un mensaje en %@", app)) }
                if parts.contains("cmd") && browsers.contains(id) { return .confirm(LF("Enviar o publicar desde %@", app)) }
                // Return in a web form or the address bar sends what was typed to a website.
                if browsers.contains(id) && target.focusedEditable { return .confirm(LF("Enviar un formulario o abrir una dirección en %@", app)) }
            }
            if target.bundleID == "com.apple.mail" && parts.contains("cmd") && parts.contains("shift") && main == "d" { return .confirm(L("Enviar un correo en Mail")) }
        case "open_app":
            let name = normalized(action.app ?? "")
            if forbiddenApps.contains(where: { name.contains($0) }) { return .block(LF("Aster no abre %@ por ti: necesita que lo hagas tú.", action.app ?? L("esa app"))) }
        case "click", "double_click":
            if let label = target.label, match(label, in: controlWords) != nil { return .confirm(LF("Pulsar «%@» en %@", shortLabel(label), app)) }
        default: break
        }
        if action.sensitive == true { return .confirm(L("Aster considera delicado este paso: ") + action.explanation) }
        if ["click", "double_click", "key", "type"].contains(action.action), match(action.explanation, in: intentWords) != nil {
            return .confirm(action.explanation)
        }
        return .allow
    }

    /// Lowercased, without accents and with single spaces, so "Envíar" and "ENVIAR" match "enviar".
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
    /// The first listed word or phrase that appears as whole words in the text.
    static func match(_ text: String, in words: [String]) -> String? {
        let tokens = normalized(text).map { $0.isLetter || $0.isNumber ? String($0) : " " }.joined()
        let haystack = " " + tokens.split(separator: " ").joined(separator: " ") + " "
        return words.first { haystack.contains(" " + $0 + " ") }
    }
    private static func shortLabel(_ label: String) -> String { String(label.split(separator: "·").first.map(String.init)?.trimmingCharacters(in: .whitespaces).prefix(60) ?? "") }

    /// Payment card numbers (Luhn), common API key formats and private keys.
    static func containsSecret(_ text: String) -> Bool {
        for candidate in text.components(separatedBy: CharacterSet(charactersIn: "0123456789 -").inverted) where candidate.filter(\.isNumber).count >= 13 {
            let number = candidate.filter(\.isNumber)
            if (13...19).contains(number.count), luhn(number) { return true }
        }
        let patterns = [#"sk-[A-Za-z0-9_\-]{16,}"#, #"gh[pousr]_[A-Za-z0-9]{20,}"#, #"AKIA[0-9A-Z]{16}"#, #"xox[abpr]-[A-Za-z0-9\-]{10,}"#, #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#, #"AIza[0-9A-Za-z_\-]{30,}"#]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }
    static func luhn(_ number: String) -> Bool {
        var sum = 0
        for (index, character) in number.reversed().enumerated() {
            guard var digit = character.wholeNumberValue else { return false }
            if index % 2 == 1 { digit *= 2; if digit > 9 { digit -= 9 } }
            sum += digit
        }
        return sum % 10 == 0
    }
}
