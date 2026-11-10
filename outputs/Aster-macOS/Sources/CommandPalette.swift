import SwiftUI

/// Something the palette can do or open.
struct PaletteCommand: Identifiable {
    var id: String
    var title: String
    var subtitle: String = ""
    var symbol: String
    var group: String
    var hint: String = ""
    var run: () -> Void

    /// Folds case and accents, so "ajustes", "Ajustés" and "AJUSTES" are the same search.
    static func fold(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    /// Commands whose title or subtitle contains every word of the query. Titles that start
    /// with the query come first; otherwise the original order is kept.
    static func matching(_ commands: [PaletteCommand], query: String) -> [PaletteCommand] {
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return commands }
        let whole = words.joined(separator: " ")
        let hits = commands.enumerated().filter { _, command in
            let text = fold(command.title + " " + command.subtitle)
            return words.allSatisfy(text.contains)
        }
        return hits.sorted { a, b in
            let first = fold(a.element.title).hasPrefix(whole), second = fold(b.element.title).hasPrefix(whole)
            return first != second ? first : a.offset < b.offset
        }.map(\.element)
    }
}

/// ⌘K: jump to any page, project or conversation, switch mode, or start something, from the keyboard.
struct CommandPalette: View {
    @EnvironmentObject var store: AsterStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("AsterAppearance") private var appearance = AsterAppearance.system.rawValue
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool
    var focusComposer: () -> Void
    var showCompanion: () -> Void

    private func go(_ page: String) { store.page = page }
    /// Everything on offer, in the order shown when nothing is typed.
    private var commands: [PaletteCommand] {
        var items: [PaletteCommand] = [
            .init(id: "new-mission", title: L("Nueva misión"), symbol: "square.and.pencil", group: "Acciones", hint: "⌘N") { store.selectedMission = nil; go("Misiones"); focusComposer() },
            .init(id: "new-task", title: L("Nueva tarea"), symbol: "plus.circle", group: "Acciones") { go("Tareas") },
            .init(id: "new-project", title: L("Nuevo proyecto"), symbol: "folder.badge.plus", group: "Acciones") { store.selectedProject = nil; go("Proyectos") },
            .init(id: "coach", title: L("A tu lado"), subtitle: L("Aster explica lo que hay en tu pantalla"), symbol: "cursorarrow.rays", group: "Acciones", hint: "⌥⌘K") { store.onOpenCoach?() },
            .init(id: "desktop", title: L("Mostrar Aster en el escritorio"), symbol: "macwindow.on.rectangle", group: "Acciones", run: showCompanion),
            .init(id: "scan", title: L("Revisar ahora"), subtitle: L("Bandeja"), symbol: "arrow.clockwise", group: "Acciones") { go("Bandeja"); Task { await store.scan() } }
        ]
        if store.speaking { items.insert(.init(id: "stop-voice", title: L("Detener voz"), symbol: "speaker.slash", group: "Acciones") { store.voice.stop() }, at: 0) }
        for (index, page) in AsterPage.all.enumerated() {
            items.append(.init(id: "page-" + page.id, title: L(AsterPage.title(page.id)), symbol: page.symbol, group: "Ir a", hint: "⌘\(index + 1)") { go(page.id) })
        }
        for mode in Specialist.modeOrder.compactMap({ id in store.state.specialists.first { $0.id == id } }) {
            items.append(.init(id: "mode-" + mode.id, title: mode.mode, subtitle: L(mode.role), symbol: mode.symbol, group: "Modos") { store.select(mode.id); go("Personajes") })
        }
        for project in store.companies {
            items.append(.init(id: "project-" + project.id.uuidString, title: project.name, subtitle: project.goal, symbol: project.template.symbol, group: "Proyectos") { store.selectedProject = project.id; go("Proyectos") })
        }
        let missions = store.state.missions.filter { $0.archived != true }.sorted { $0.updated > $1.updated }
        for mission in query.isEmpty ? Array(missions.prefix(5)) : missions {
            items.append(.init(id: "mission-" + mission.id.uuidString, title: mission.title, subtitle: L(mission.status), symbol: "bubble.left", group: "Misiones") { store.openMission(mission.id) })
        }
        if !query.isEmpty {
            for task in store.openTasks {
                items.append(.init(id: "task-" + task.id.uuidString, title: task.title, subtitle: L("Tarea"), symbol: "circle", group: "Tareas") { go("Tareas") })
            }
        }
        for value in AsterAppearance.allCases {
            items.append(.init(id: "appearance-" + value.rawValue, title: L("Apariencia") + ": " + L(value.rawValue), symbol: value.symbol, group: "Apariencia") { appearance = value.rawValue })
        }
        return items
    }
    private var results: [PaletteCommand] {
        var found = Array(PaletteCommand.matching(commands, query: query).prefix(40))
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            found.append(.init(id: "ask", title: LF("Preguntar a Aster: «%@»", text), symbol: "sparkle", group: "Aster") { if store.run(text, fresh: true) { go("Misiones") } })
        }
        return found
    }

    var body: some View {
        let results = results
        ZStack(alignment: .top) {
            Color.black.opacity(0.22).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { close() }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(Color.asterMuted)
                    TextField(L("Buscar o saltar a…"), text: $query).textFieldStyle(.plain).font(.system(size: 16)).focused($focused)
                        .onSubmit { run(results) }
                        .onKeyPress(.downArrow) { move(1, in: results); return .handled }
                        .onKeyPress(.upArrow) { move(-1, in: results); return .handled }
                    KeyCap("esc")
                }.padding(.horizontal, 18).frame(height: 54)
                Rectangle().fill(Color.asterHairline).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                                if index == 0 || results[index - 1].group != command.group {
                                    MonoLabel(L(command.group), size: 9).padding(.horizontal, 12).padding(.top, index == 0 ? 4 : 10).padding(.bottom, 3)
                                }
                                row(command, selected: index == selection).id(command.id)
                                    .onTapGesture { selection = index; run(results) }
                                    .onHover { if $0 { selection = index } }
                            }
                        }.padding(8)
                    }.frame(maxHeight: 372).scrollIndicators(.hidden)
                        .onChange(of: selection) { _, value in if results.indices.contains(value) { proxy.scrollTo(results[value].id) } }
                }
                Rectangle().fill(Color.asterHairline).frame(height: 1)
                HStack(spacing: 14) {
                    hint("↑↓", "moverse"); hint("↵", "abrir"); hint("esc", "cerrar")
                    Spacer()
                    Text("Aster").font(.asterDisplay(11)).foregroundStyle(Color.asterMuted)
                }.padding(.horizontal, 16).frame(height: 34)
            }
            .frame(width: 580)
            // A wash of the canvas keeps the list readable whatever page is behind the glass.
            .background(Color.asterCanvas.opacity(0.55), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .glassChrome(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.top, 96)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97, anchor: .top)).combined(with: .offset(y: -8)))
        }
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selection = 0 }
        .onExitCommand { close() }
        .accessibilityAddTraits(.isModal)
    }

    private func row(_ command: PaletteCommand, selected: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: command.symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(selected ? Color.asterAccent : Color.asterMuted).frame(width: 26, height: 26)
                .background(selected ? Color.asterAccentSoft : Color.asterWell, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(command.title).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1)
            if !command.subtitle.isEmpty { Text(command.subtitle).font(.system(size: 11.5)).foregroundStyle(Color.asterMuted).lineLimit(1) }
            Spacer(minLength: 8)
            if !command.hint.isEmpty { KeyCap(command.hint) }
            if selected { Image(systemName: "return").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.asterMuted) }
        }.padding(.horizontal, 8).frame(height: 38)
            .background(selected ? Color.asterHover : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine).accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) { KeyCap(key); Text(L(label)).font(.system(size: 10.5)).foregroundStyle(Color.asterMuted) }
    }
    private func move(_ step: Int, in results: [PaletteCommand]) {
        guard !results.isEmpty else { return }
        selection = (selection + step + results.count) % results.count
    }
    private func run(_ results: [PaletteCommand]) {
        guard results.indices.contains(selection) else { return }
        let command = results[selection]
        close(); command.run()
    }
    private func close() { store.paletteOpen = false }
}
