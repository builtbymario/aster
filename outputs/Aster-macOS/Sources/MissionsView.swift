import SwiftUI
import AppKit

/// Missions: every conversation on the left, the open one on the right.
struct MissionsView: View {
    @EnvironmentObject var store: AsterStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var draft: String
    @Binding var renaming: Mission?
    @State private var query = ""
    @State private var showArchived = false
    @State private var viewport: CGFloat = 600
    @State private var nearBottom = true
    @FocusState private var searching: Bool

    var body: some View {
        HStack(spacing: 12) {
            list
            if let mission = store.mission { conversation(mission).id(mission.id).transition(.opacity) }
            else { WorkspaceEmpty(symbol: "sparkle", title: "Una misión, una dirección", detail: "Pide algo concreto. El equipo guarda cada conversación y el estado real de su trabajo.") }
        }.padding(.horizontal, 6)
            .background(Button("") { searching = true }.keyboardShortcut("f", modifiers: .command).hidden())
    }

    // MARK: List

    private var filtered: [Mission] {
        store.state.missions.filter {
            (showArchived ? $0.archived == true : $0.archived != true) && (store.projectFilter == nil || $0.companyID == store.projectFilter)
                && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.messages.contains { $0.text.localizedCaseInsensitiveContains(query) })
        }.sorted { $0.updated > $1.updated }
    }
    /// Pinned first, then by how recently each one moved.
    static func groups(_ missions: [Mission], now: Date = Date(), calendar: Calendar = .current) -> [(title: String, items: [Mission])] {
        let today = calendar.startOfDay(for: now)
        func bucket(_ mission: Mission) -> Int {
            if mission.pinned == true { return 0 }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: mission.updated), to: today).day ?? 0
            return days <= 0 ? 1 : days == 1 ? 2 : days < 7 ? 3 : 4
        }
        let titles = ["Fijadas", "Hoy", "Ayer", "Esta semana", "Anteriores"]
        return Dictionary(grouping: missions, by: bucket).sorted { $0.key < $1.key }.map { (titles[$0.key], $0.value.sorted { $0.updated > $1.updated }) }
    }
    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Color.asterMuted)
                    TextField(L("Buscar misiones…"), text: $query).textFieldStyle(.plain).font(.system(size: 12)).focused($searching)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Color.asterMuted) }.buttonStyle(.plain).accessibilityLabel(L("Borrar búsqueda")) }
                }.padding(.horizontal, 9).frame(height: 30).background(Color.asterWell, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(searching ? Color.asterAccent.opacity(0.5) : Color.asterHairline, lineWidth: 1))
                GlassIconButton(symbol: "square.and.pencil", title: "Nueva misión") { store.selectedMission = nil; draft = "" }
            }
            HStack(spacing: 6) {
                Menu {
                    Button { store.projectFilter = nil } label: { if store.projectFilter == nil { Label(L("Todas"), systemImage: "checkmark") } else { Text(L("Todas")) } }
                    ForEach(store.companies) { project in
                        Button { store.projectFilter = project.id } label: { if store.projectFilter == project.id { Label(project.name, systemImage: "checkmark") } else { Text(project.name) } }
                    }
                } label: {
                    Label(store.companies.first { $0.id == store.projectFilter }?.name ?? L("Todas"), systemImage: "folder").font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                }.menuStyle(.borderlessButton).fixedSize().help(L("Proyecto"))
                Spacer(minLength: 0)
                ModeChip(title: L("Archivadas"), selected: showArchived) { withAnimation(AsterMotion.quick(reduceMotion)) { showArchived.toggle() } }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(Self.groups(filtered), id: \.title) { group in
                        MonoLabel(L(group.title), size: 9).padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
                        ForEach(group.items) { mission in row(mission) }
                    }
                    if filtered.isEmpty {
                        Text(L(query.isEmpty ? "Aún no hay misiones aquí." : "Nada coincide con tu búsqueda.")).font(.system(size: 11.5)).foregroundStyle(Color.asterMuted).padding(10)
                    }
                }
            }.scrollIndicators(.hidden)
        }.padding(12).frame(width: 236).frostedSurface(22)
    }
    private func statusColor(_ mission: Mission) -> Color {
        if store.isRunning(mission.id) { return .asterPollen }
        switch mission.status { case "Completada": return .green; case "Fallida", "Necesita revisión", "Por recuperar": return .red; default: return .asterMuted.opacity(0.6) }
    }
    private func row(_ mission: Mission) -> some View {
        let selected = store.selectedMission == mission.id
        return Button { store.openMission(mission.id); nearBottom = true } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(statusColor(mission)).frame(width: 6, height: 6).padding(.top, 5)
                VStack(alignment: .leading, spacing: 3) {
                    Text(mission.title).font(.system(size: 12, weight: selected ? .semibold : .medium)).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        if mission.pinned == true { Image(systemName: "pin.fill").font(.system(size: 7.5)) }
                        Text(L(mission.status)).lineLimit(1)
                        Text("·")
                        Text(AsterDate.relative(mission.updated)).lineLimit(1)
                    }.font(.system(size: 10)).foregroundStyle(Color.asterMuted)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 9).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Color.asterAccentSoft : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .hoverFill(11, active: selected).contentShape(Rectangle())
        }.buttonStyle(.plain).contextMenu { menu(mission) }
    }
    @ViewBuilder private func menu(_ mission: Mission) -> some View {
        Button(L("Renombrar")) { renaming = mission }
        Button(L(mission.pinned == true ? "Desfijar" : "Fijar")) { store.pinMission(mission.id) }
        Button(L(mission.archived == true ? "Restaurar" : "Archivar")) { store.archiveMission(mission.id, archived: mission.archived != true) }.disabled(store.isRunning(mission.id))
        Divider()
        Button(L("Eliminar"), role: .destructive) { withAnimation(AsterMotion.spring(reduceMotion)) { store.deleteMission(mission.id) } }.disabled(store.isRunning(mission.id))
    }

    // MARK: Conversation

    private func conversation(_ mission: Mission) -> some View {
        let agent = store.state.specialists.first { $0.id == mission.specialistID }
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(mission.title).font(.asterDisplay(15)).lineLimit(1)
                    HStack(spacing: 5) {
                        Text(L(mission.status))
                        if let seconds = mission.elapsedSeconds { Text("· " + String(format: "%.0f s", seconds)) }
                        if let company = store.state.companies.first(where: { $0.id == mission.companyID }) { Text("· " + company.name) }
                    }.font(.system(size: 10.5)).foregroundStyle(Color.asterMuted)
                }
                Spacer()
                GlassIconButton(symbol: "arrow.clockwise", title: "Recuperar estado y trabajo guardado", action: { store.recover() }).disabled(store.isRunning(mission.id) || !store.hasCapacity || mission.sessionID == nil)
                GlassIconButton(symbol: "square.and.arrow.up", title: "Exportar conversación", action: store.exportMission)
                GlassIconButton(symbol: "folder", title: "Cargar archivos creados", action: store.loadArtifacts).disabled(store.isRunning(mission.id) || !store.hasCapacity || mission.sessionID == nil)
                Menu { menu(mission) } label: { Image(systemName: "ellipsis").frame(width: 26, height: 26) }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26).disabled(store.isRunning(mission.id))
            }.padding(.horizontal, 18).padding(.vertical, 12)
            Rectangle().fill(Color.asterHairline).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(mission.messages.filter { !$0.text.isEmpty }) { message in
                            MessageRow(message: message, agentStyle: agent?.style ?? AvatarStyle(), agentTitle: agent?.title ?? "Aster", agentID: mission.specialistID)
                        }
                        if !store.isRunning(mission.id), let learned = mission.learned { LearnedNote(facts: learned) { store.forgetLearned($0, in: mission.id) } }
                        if !store.isRunning(mission.id), let steps = mission.suggestions, !steps.isEmpty {
                            NextSteps(steps: steps, enabled: store.hasCapacity) { step in
                                if mission.engine == "direct", store.desktopMission(for: mission.specialistID)?.id == mission.id { store.sendDesktop(step, agentID: mission.specialistID) }
                                else { store.selectedMission = mission.id; store.run(step) }
                            }.frame(maxWidth: 520, alignment: .leading)
                        }
                        if let error = mission.error { attention(mission, error: error) }
                        if store.isRunning(mission.id) {
                            HStack(spacing: 9) { ThinkingDots(); Text(L(store.activity(for: mission.id))).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.asterPollen).contentTransition(.opacity) }
                        }
                        ForEach(store.artifacts) { artifact in
                            Button { store.downloadArtifact(artifact) } label: { Label(URL(fileURLWithPath: artifact.path).lastPathComponent, systemImage: "arrow.down.doc") }.glassControl().font(.system(size: 11))
                        }
                        Color.clear.frame(height: 1).id("bottom").background(GeometryReader { geo in Color.clear.preference(key: MessageBottomKey.self, value: geo.frame(in: .named("messages")).minY) })
                    }.padding(.horizontal, 22).padding(.vertical, 20).frame(maxWidth: 780, alignment: .leading).frame(maxWidth: .infinity)
                }.coordinateSpace(name: "messages")
                    .background(GeometryReader { geo in Color.clear.onAppear { viewport = geo.size.height }.onChange(of: geo.size.height) { _, size in viewport = size } })
                    .onPreferenceChange(MessageBottomKey.self) { bottom in nearBottom = bottom <= viewport + 150 }
                    .onChange(of: mission.messages.last?.text) { _, _ in if nearBottom { proxy.scrollTo("bottom", anchor: .bottom) } }
                    .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                    .overlay(alignment: .bottom) {
                        if !nearBottom {
                            Button { nearBottom = true; withAnimation(AsterMotion.spring(reduceMotion)) { proxy.scrollTo("bottom", anchor: .bottom) } } label: {
                                Image(systemName: "arrow.down").font(.system(size: 12, weight: .semibold)).frame(width: 32, height: 32).glassChrome(Circle(), interactive: true)
                            }.buttonStyle(FluidButtonStyle()).accessibilityLabel(L("Ver lo último")).padding(12).transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }.animation(AsterMotion.quick(reduceMotion), value: nearBottom)
            }
        }.frostedSurface(22)
    }
    private func attention(_ mission: Mission, error: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("Esta misión necesita atención"), systemImage: "exclamationmark.circle").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.orange)
            Text(L(error)).font(.system(size: 12)).foregroundStyle(Color.asterMuted).textSelection(.enabled)
            HStack {
                Button(L("Recuperar estado"), action: { store.recover() }).glassControl().disabled(store.isRunning(mission.id) || !store.hasCapacity || mission.sessionID == nil)
                if error.contains("facturación") || error.contains("saldo") { let provider: AIProvider = store.settings.usesClaude ? .anthropic : .openai; Link(LF("Revisar cuenta de %@", provider.name), destination: provider.billingURL) }
            }.font(.system(size: 11))
        }.padding(16).frostedSurface(16, tint: .orange)
    }
}

/// One message. Yours sits to the right in the accent; Aster's reads full width, with its
/// actions appearing under the pointer.
private struct MessageRow: View {
    @EnvironmentObject var store: AsterStore
    var message: Message
    var agentStyle: AvatarStyle
    var agentTitle: String
    var agentID: String
    @State private var hovering = false
    @State private var copied = false
    var body: some View {
        Group {
            if message.role == "user" {
                HStack(alignment: .bottom, spacing: 6) {
                    Spacer(minLength: 60)
                    actions.opacity(hovering ? 1 : 0)
                    Text(verbatim: message.text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.asterAccentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.asterAccent.opacity(0.14), lineWidth: 1))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        CompanionAvatar(style: agentStyle, mood: .calm, dimension: 20, animateAtRest: false, framesPerSecond: 12).accessibilityHidden(true)
                        Text(agentTitle).font(.asterDisplay(12, weight: .semibold))
                        Text(AsterDate.stamp(message.date, date: .omitted, time: .shortened)).font(.system(size: 10)).foregroundStyle(Color.asterMuted)
                        Spacer()
                        actions.opacity(hovering ? 1 : 0)
                    }
                    RichMessage(text: AsterMarkup.display(message.text)).equatable()
                }
            }
        }.onHover { hovering = $0 }.animation(.easeOut(duration: 0.14), value: hovering)
    }
    private var actions: some View {
        HStack(spacing: 2) {
            if message.role == "assistant" {
                action(store.speaking ? "stop.circle" : "speaker.wave.2", "Leer en voz alta") { store.speak(message.text, agentID: agentID) }
            }
            action(copied ? "checkmark" : "doc.on.doc", "Copiar mensaje") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string)
                copied = true; Task { try? await Task.sleep(for: .seconds(1.4)); copied = false }
            }
        }
    }
    private func action(_ symbol: String, _ title: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color.asterMuted).frame(width: 24, height: 24).hoverFill(Circle()).contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }.buttonStyle(.plain).accessibilityLabel(L(title)).help(L(title))
    }
}

private struct MessageBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The inbox: what the team wrote while the user was away.
struct InboxView: View {
    @EnvironmentObject var store: AsterStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var unreadOnly = false
    private var notes: [InboxNote] { store.state.inbox.filter { !unreadOnly || !$0.read } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "El equipo te escribe.", subtitle: "Novedades, propuestas y lo que necesita tu atención.") {
                    if store.unread > 0 { GlassAction(title: "Marcar todo como leído", symbol: "checkmark.circle") { withAnimation(AsterMotion.spring(reduceMotion)) { store.markAllRead() } } }
                    GlassAction(title: "Revisar ahora", symbol: "arrow.clockwise", prominent: true) { Task { await store.scan() } }
                }
                if !store.state.inbox.isEmpty {
                    GlassSegmented(options: [(false, L("Todas")), (true, LF("Sin leer · %d", store.unread))], selection: $unreadOnly).frame(width: 240)
                }
                if notes.isEmpty {
                    WorkspaceEmpty(symbol: "tray", title: unreadOnly ? "Todo leído" : "Todo tranquilo por aquí", detail: unreadOnly ? "No queda nada pendiente de leer." : "Conecta tu agenda o Apple Mail para recibir novedades. También verás los resultados de las misiones autónomas.")
                }
                ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in InboxCard(note: note).arrive(index) }
            }.padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 24).frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity)
                .animation(AsterMotion.spring(reduceMotion), value: notes.map(\.id))
        }.scrollIndicators(.hidden)
    }
}

private struct InboxCard: View {
    @EnvironmentObject var store: AsterStore
    var note: InboxNote
    @State private var hovering = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                if !note.read { Circle().fill(Color.asterAccent).frame(width: 7, height: 7).shadow(color: Color.asterAccent.opacity(0.6), radius: 3) }
                Text(note.title).font(.system(size: 14, weight: note.read ? .medium : .semibold)).lineLimit(2)
                Spacer()
                Text(AsterDate.relative(note.date)).font(.system(size: 10.5)).foregroundStyle(Color.asterMuted)
                Button { store.deleteNote(note.id) } label: { Image(systemName: "trash").font(.system(size: 10.5)).foregroundStyle(Color.asterMuted).frame(width: 24, height: 24).hoverFill(Circle()).contentShape(Circle()) }
                    .buttonStyle(.plain).opacity(hovering ? 1 : 0).accessibilityLabel(L("Eliminar")).help(L("Eliminar"))
            }
            Text(note.text).font(.system(size: 12.5)).foregroundStyle(note.read ? Color.asterMuted : Color.primary.opacity(0.85)).lineSpacing(4).textSelection(.enabled)
            if note.missionID != nil || !note.read {
                HStack(spacing: 8) {
                    if let id = note.missionID, store.state.missions.contains(where: { $0.id == id }) { Button(L("Abrir misión")) { store.openMission(id); store.markRead(note.id) } }
                    if !note.read { Button(L("Marcar como leído")) { store.markRead(note.id) } }
                }.font(.system(size: 11)).glassControl().padding(.top, 2)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).frostedSurface(20)
            .onHover { hovering = $0 }.animation(.easeOut(duration: 0.14), value: hovering)
            .contextMenu {
                if !note.read { Button(L("Marcar como leído")) { store.markRead(note.id) } }
                Button(L("Eliminar"), role: .destructive) { store.deleteNote(note.id) }
            }
    }
}
