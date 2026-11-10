import Foundation
import SwiftUI

enum AsterLanguage: String, CaseIterable {
    case spanish = "es", english = "en"
    var name: String { switch self { case .spanish: return "Español"; case .english: return "English" } }
    /// The interface language; anything no longer offered falls back to Spanish.
    static func migrateStoredChoice(_ defaults: UserDefaults = .standard) {
        if let stored = defaults.string(forKey: "AsterLanguage"), Self(rawValue: stored) == nil { defaults.set(Self.spanish.rawValue, forKey: "AsterLanguage") }
    }
}
private enum TranslationCatalog {
    static let values: [String: [String: String]] = {
        var catalogs: [String: [String: String]] = [:]
        for code in ["en"] {
            if let url = Bundle.main.url(forResource: code, withExtension: "json", subdirectory: "Localization"), let data = try? Data(contentsOf: url), let catalog = try? JSONDecoder().decode([String: String].self, from: data) { catalogs[code] = catalog }
        }
        return catalogs
    }()
}
func L(_ key: String, language: String? = nil) -> String {
    let language = language ?? UserDefaults.standard.string(forKey: "AsterLanguage") ?? "es"
    return TranslationCatalog.values[language]?[key] ?? key
}
func LF(_ key: String, _ arguments: CVarArg...) -> String { String(format: L(key), locale: Locale(identifier: UserDefaults.standard.string(forKey: "AsterLanguage") ?? "es"), arguments: arguments) }

/// Dates as the interface speaks them: in its language, not the Mac's.
enum AsterDate {
    static var locale: Locale { Locale(identifier: UserDefaults.standard.string(forKey: "AsterLanguage") ?? "es") }
    /// "hace 5 horas", "ayer".
    static func relative(_ date: Date) -> String { date.formatted(Date.RelativeFormatStyle(presentation: .named, locale: locale)) }
    /// "8 nov".
    static func day(_ date: Date) -> String { date.formatted(Date.FormatStyle(locale: locale).day().month(.abbreviated)) }
    /// "Lunes, 9 de noviembre".
    static func today(_ date: Date = Date()) -> String {
        let text = date.formatted(Date.FormatStyle(locale: locale).weekday(.wide).day().month(.wide))
        return text.prefix(1).uppercased() + text.dropFirst()
    }
    static func weekday(_ date: Date) -> String { date.formatted(Date.FormatStyle(locale: locale).weekday(.narrow)) }
    static func stamp(_ date: Date, date dateStyle: Date.FormatStyle.DateStyle = .abbreviated, time: Date.FormatStyle.TimeStyle = .shortened) -> String {
        date.formatted(Date.FormatStyle(date: dateStyle, time: time, locale: locale))
    }
}
