import SwiftUI
import AppKit

/// One block of an answer: a paragraph, a heading, code, a list, a quote, a table or a rule.
struct MessageBlock: Identifiable {
    enum Kind { case text, code(String), heading(Int), list, quote, table, rule }
    struct Item: Equatable {
        /// "•", "1.", "☐" or "☑".
        var marker: String
        var depth: Int
        var text: String
    }
    var id: Int
    var kind: Kind
    var text: String
    var items: [Item] = []
    /// A table's rows of cells; the first row is its header.
    var rows: [[String]] = []

    private enum Open { case text, quote, list, table }

    static func parse(_ text: String) -> [MessageBlock] {
        var blocks: [MessageBlock] = []; var buffer: [String] = []; var open = Open.text; var code: String?
        func add(_ kind: Kind, _ text: String, items: [Item] = [], rows: [[String]] = []) { blocks.append(.init(id: blocks.count, kind: kind, text: text, items: items, rows: rows)) }
        func flush() {
            defer { buffer = []; open = .text }
            guard !buffer.isEmpty else { return }
            if let code { add(.code(code), buffer.joined(separator: "\n")); return }
            switch open {
            case .text: add(.text, buffer.joined(separator: "\n"))
            case .quote: add(.quote, buffer.map { String($0.drop { $0 == " " }.dropFirst()).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n"))
            case .list: add(.list, buffer.joined(separator: "\n"), items: buffer.compactMap(item))
            case .table:
                let rows = buffer.map(cells)
                // A table needs its header and the row of dashes under it; anything else is just text.
                if rows.count >= 2, rows[1].allSatisfy({ !$0.isEmpty && $0.allSatisfy { "-: ".contains($0) } }) { add(.table, buffer.joined(separator: "\n"), rows: [rows[0]] + rows.dropFirst(2)) }
                else { add(.text, buffer.joined(separator: "\n")) }
            }
        }
        func take(_ line: String, as kind: Open) { if open != kind { flush(); open = kind }; buffer.append(line) }
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if code != nil { flush(); code = nil } else { flush(); code = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
                continue
            }
            if code != nil { buffer.append(line); continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { flush() }
            else if line.hasPrefix("#"), let space = line.firstIndex(of: " "), line[..<space].allSatisfy({ $0 == "#" }) {
                flush(); add(.heading(min(4, line[..<space].count)), String(line[line.index(after: space)...]))
            }
            else if ["---", "***", "___"].contains(trimmed) { flush(); add(.rule, "") }
            else if trimmed.hasPrefix(">") { take(line, as: .quote) }
            else if trimmed.hasPrefix("|") { take(line, as: .table) }
            else if item(line) != nil { take(line, as: .list) }
            // A wrapped line continues the list item or quote above it.
            else if open == .list, line.hasPrefix("  "), !buffer.isEmpty { buffer[buffer.count - 1] += " " + trimmed }
            else { take(line, as: .text) }
        }
        flush(); return blocks
    }

    /// "- text", "* text", "1. text" or "- [x] text", with two spaces of indent per level.
    static func item(_ line: String) -> Item? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
        let body = line.drop { $0 == " " || $0 == "\t" }
        guard let space = body.firstIndex(of: " ") else { return nil }
        let marker = body[..<space]; var rest = String(body[body.index(after: space)...])
        guard !rest.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if ["-", "*", "•", "+"].contains(String(marker)) {
            if rest.hasPrefix("[ ] ") { rest.removeFirst(4); return Item(marker: "☐", depth: indent / 2, text: rest) }
            if rest.lowercased().hasPrefix("[x] ") { rest.removeFirst(4); return Item(marker: "☑", depth: indent / 2, text: rest) }
            return Item(marker: "•", depth: indent / 2, text: rest)
        }
        if marker.count <= 4, let last = marker.last, last == "." || last == ")", !marker.dropLast().isEmpty, marker.dropLast().allSatisfy(\.isNumber) {
            return Item(marker: marker.dropLast() + ".", depth: indent / 2, text: rest)
        }
        return nil
    }
    static func cells(_ line: String) -> [String] {
        var parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.first == "" { parts.removeFirst() }; if parts.last == "" { parts.removeLast() }
        return parts
    }
}

/// Answers are re-read on every redraw while one streams; each text is parsed once.
private final class MessageBlockCache {
    static let shared = MessageBlockCache()
    private let cache = NSCache<NSString, Entry>()
    private final class Entry { let blocks: [MessageBlock]; init(_ blocks: [MessageBlock]) { self.blocks = blocks } }
    init() { cache.countLimit = 240 }
    func blocks(for text: String) -> [MessageBlock] {
        let key = text as NSString
        if let entry = cache.object(forKey: key) { return entry.blocks }
        let blocks = MessageBlock.parse(text); cache.setObject(Entry(blocks), forKey: key); return blocks
    }
}

/// Links in answers can come from untrusted pages or emails, so only web and mail addresses open.
enum SafeLinks {
    static let schemes: Set<String> = ["http", "https", "mailto"]
    static func allows(_ url: URL) -> Bool { schemes.contains(url.scheme?.lowercased() ?? "") }
    static let action = OpenURLAction { url in allows(url) ? .systemAction : .discarded }
}

struct RichMessage: View, Equatable {
    var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(MessageBlockCache.shared.blocks(for: text)) { block in
                switch block.kind {
                case .code(let language): CodeBlock(language: language, code: block.text)
                case .heading(let level): Text(.init(block.text)).font(.asterDisplay(level == 1 ? 21 : level == 2 ? 17 : 14.5)).textSelection(.enabled).padding(.top, 4)
                case .text: Text(.init(block.text)).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                case .list: list(block.items)
                case .quote:
                    HStack(alignment: .top, spacing: 11) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Color.asterAccent.opacity(0.55)).frame(width: 3)
                        Text(.init(block.text)).font(.system(size: 13)).lineSpacing(5).foregroundStyle(.secondary).textSelection(.enabled)
                    }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 2)
                case .table: table(block.rows)
                case .rule: Rectangle().fill(Color.asterHairlineStrong).frame(height: 1).padding(.vertical, 4)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, SafeLinks.action)
    }

    private func list(_ items: [MessageBlock.Item]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Group {
                        if item.marker == "•" { Circle().fill(Color.asterAccent.opacity(0.7)).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 } }
                        else if item.marker == "☐" || item.marker == "☑" { Image(systemName: item.marker == "☑" ? "checkmark.square.fill" : "square").font(.system(size: 12)).foregroundStyle(item.marker == "☑" ? Color.asterAccent : Color.asterMuted) }
                        else { Text(item.marker).font(.system(size: 12.5, weight: .medium).monospacedDigit()).foregroundStyle(Color.asterMuted) }
                    }.frame(minWidth: 16, alignment: .trailing)
                    Text(.init(item.text)).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.leading, CGFloat(min(item.depth, 4)) * 18)
            }
        }
    }

    private func table(_ rows: [[String]]) -> some View {
        let columns = rows.map(\.count).max() ?? 0
        return Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        Text(.init(column < row.count ? row[column] : "")).font(.system(size: 12.5, weight: index == 0 ? .semibold : .regular))
                            .foregroundStyle(index == 0 ? Color.asterMuted : Color.primary).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
                    }
                }
                if index < rows.count - 1 { Rectangle().fill(index == 0 ? Color.asterHairlineStrong : Color.asterHairline).frame(height: 1).gridCellColumns(max(1, columns)) }
            }
        }.padding(.horizontal, 14).padding(.vertical, 3)
            .background(Color.asterWell, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.asterHairline, lineWidth: 1))
    }
}

private struct CodeBlock: View {
    var language: String
    var code: String
    @State private var copied = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? L("Código") : language).font(.asterMono(10)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string)
                    copied = true; Task { try? await Task.sleep(for: .seconds(1.4)); copied = false }
                } label: { Label(L(copied ? "Copiado" : "Copiar"), systemImage: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10, weight: .medium)).contentTransition(.symbolEffect(.replace)) }
                    .buttonStyle(.plain).foregroundStyle(copied ? Color.asterAccent : Color.secondary)
            }.padding(.horizontal, 13).padding(.vertical, 8).background(Color.asterWell)
            ScrollView(.horizontal) { Text(verbatim: code).font(.system(size: 11.5, design: .monospaced)).lineSpacing(4).textSelection(.enabled).padding(14).frame(maxWidth: .infinity, alignment: .leading) }
        }.background(Color.asterWell, in: shape).clipShape(shape).overlay(shape.strokeBorder(Color.asterHairline, lineWidth: 1))
    }
}
