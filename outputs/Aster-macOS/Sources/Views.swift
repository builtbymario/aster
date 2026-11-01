import SwiftUI
import AppKit

private let ink = Color.primary
private let paper = Color(nsColor: .windowBackgroundColor)
private let muted = Color.secondary

struct MainView: View {
    @EnvironmentObject var store: AsterStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @AppStorage("AsterAppearance") private var appearance = AsterAppearance.system.rawValue
    @AppStorage("AsterLanguage") private var language = "es"
    @Namespace private var navigationNamespace
    @Namespace private var agentNamespace
    @State private var draft = ""
    @State private var customizing = false
    @State private var renamingMission: Mission?
    @State private var missionQuery = ""
    @State private var showArchived = false
    @State private var messageViewport: CGFloat = 600
    @State private var nearBottom = true
    @State private var showNotice = false
    @State private var choosingAppearance = false
    @FocusState private var composerFocused: Bool
    var showCompanion: () -> Void
    /// The places people use every day; the rest sit below, smaller. Settings live in the toolbar.
    let pages = [("Personajes", "sparkles"), ("Proyectos", "folder"), ("Misiones", "square.stack.3d.up"), ("Tareas", "checklist"), ("Bandeja", "tray")]
    let morePages = [("Actividad", "waveform.path"), ("Ordenador", "cursorarrow.motionlines"), ("Memoria", "brain")]
    var body: some View {
        HStack(spacing: 18) {
            sidebar
            VStack(spacing: 0) {
                toolbar
                pageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(store.page)
                    .transition(.opacity)
                if !["Conexiones", "Memoria", "Tareas", "Ordenador", "Actividad", "Proyectos"].contains(store.page) { composer.transition(.opacity.combined(with: .move(edge: .bottom))) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14).padding(.top, 10)
        .frame(minWidth: 1020, minHeight: 760)
        .background(AmbientBackdrop(tint: Color.asterAccent))
        .foregroundStyle(.primary)
        .tint(Color.asterAccent)
        .preferredColorScheme(AsterAppearance(rawValue: appearance)?.scheme)
        .environment(\.locale, Locale(identifier: language))
        .animation(AsterMotion.quick(reduceMotion), value: store.page)
        .sheet(isPresented: $customizing) { CustomizeView(original: store.agent) { store.updateAgent($0) } }
        .sheet(item: $renamingMission) { RenameMissionView(mission: $0) }
        .background(Button(L("")) { composerFocused = true }.keyboardShortcut("l", modifiers: .command).hidden())
        .onChange(of: store.notice) { _, new in if !new.isEmpty { showNotice = true } }
        .alert("Aster", isPresented: $showNotice) { Button(L("Entendido")) { store.notice = "" } } message: { Text(L(store.notice)) }
        .accessibilityHidden(store.onboarding)
        .overlay { if store.onboarding { OnboardingView().transition(.opacity) } }
        .animation(AsterMotion.spring(reduceMotion), value: store.onboarding)
    }
    /// Display name of a page; the internal identifiers stay unchanged.
    private func pageTitle(_ page: String) -> String { ["Personajes": "Inicio", "Conexiones": "Ajustes"][page] ?? page }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                CompanionAvatar(style: store.state.specialists.first { $0.id == "director" }?.style ?? AvatarStyle(), mood: store.mood(), dimension: 34, animateAtRest: false, framesPerSecond: 30)
                Text("aster").font(.asterDisplay(23, weight: .bold)).tracking(-0.4)
            }.padding(.top, 22).padding(.bottom, 24)
            ForEach(pages, id: \.0) { item in
                Button { navigate(item.0) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.1).font(.system(size: 13, weight: .medium)).frame(width: 18).foregroundStyle(store.page == item.0 ? Color.asterAccent : Color.secondary)
                        Text(L(pageTitle(item.0))).font(.system(size: 12.5, weight: store.page == item.0 ? .semibold : .regular))
                        Spacer(minLength: 0)
                        if item.0 == "Bandeja" && store.unread > 0 {
                            Text("\(store.unread)").font(.system(size: 9.5, weight: .bold, design: .rounded)).frame(minWidth: 18, minHeight: 17).foregroundStyle(Color.asterInk).background(Color.asterRing, in: Capsule())
                        }
                    }.padding(.horizontal, 10).frame(height: 32)
                        .foregroundStyle(store.page == item.0 ? Color.asterAccentText : Color.secondary)
                        .background {
                            if store.page == item.0 {
                                Capsule(style: .continuous).fill(Color.asterAccentSoft)
                                    .matchedGeometryEffect(id: "navigation", in: navigationNamespace)
                            }
                        }
                }.buttonStyle(FluidButtonStyle()).accessibilityAddTraits(store.page == item.0 ? .isSelected : []).padding(.bottom, 3)
            }
            if !store.companies.isEmpty {
                HStack { MonoLabel(L("Proyectos"), size: 9); Spacer() }.padding(.top, 14).padding(.bottom, 6)
                ForEach(store.companies.prefix(6)) { project in
                    let open = store.page == "Proyectos" && (store.selectedProject ?? store.companies.first?.id) == project.id
                    Button { store.selectedProject = project.id; navigate("Proyectos") } label: {
                        HStack(spacing: 9) {
                            Image(systemName: project.template.symbol).font(.system(size: 10, weight: .medium)).frame(width: 16).foregroundStyle(open ? Color.asterAccent : muted)
                            Text(project.name).font(.system(size: 11.5, weight: open ? .semibold : .regular)).lineLimit(1)
                            Spacer(minLength: 2)
                            if store.isRunning(store.projectChat(project.id)?.id) { Circle().fill(Color.asterPollen).frame(width: 6, height: 6) }
                        }.foregroundStyle(open ? Color.primary : Color.secondary).frame(height: 26).padding(.horizontal, 10).contentShape(Rectangle())
                    }.buttonStyle(FluidButtonStyle())
                }
            }
            Spacer(minLength: 10)
            ForEach(morePages, id: \.0) { item in
                Button { navigate(item.0) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.1).font(.system(size: 10, weight: .medium)).frame(width: 16)
                        Text(L(item.0)).font(.system(size: 11, weight: store.page == item.0 ? .semibold : .regular))
                        Spacer(minLength: 0)
                    }.foregroundStyle(store.page == item.0 ? Color.primary : Color.secondary).frame(height: 24).padding(.horizontal, 10).contentShape(Rectangle())
                }.buttonStyle(FluidButtonStyle()).accessibilityAddTraits(store.page == item.0 ? .isSelected : [])
            }
            Rectangle().fill(Color.asterHairline).frame(height: 1).padding(.vertical, 16)
            Button(action: showCompanion) {
                HStack(spacing: 9) {
                    Image(systemName: "macwindow.on.rectangle").font(.system(size: 13))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("En tu escritorio")).font(.system(size: 11, weight: .medium))
                        Text(L("Siempre a mano")).font(.system(size: 9)).foregroundStyle(muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(muted)
                }.padding(.vertical, 7)
            }.buttonStyle(FluidButtonStyle()).accessibilityLabel(L("Mostrar compañeros en el escritorio")).padding(.bottom, 18)
        }.padding(.horizontal, 17).frame(width: 183).frame(maxHeight: .infinity).frostedSurface(25)
    }
    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(L(pageTitle(store.page))).font(.asterDisplay(17)).padding(.leading, 6).opacity(store.page == "Personajes" ? 0 : 1)
            Spacer()
            LiquidGroup(spacing: 12) {
                HStack(spacing: 10) {
                    HStack(spacing: 7) {
                        Circle().fill(store.busy ? Color.asterPollen : store.connectionReady ? Color.green : Color.orange).frame(width: 6, height: 6)
                        Text(L(store.busy ? "Trabajando" : store.connectionStatus.hasPrefix("Conectado a") ? "Conectado" : store.connectionReady ? "Clave válida" : "Conexión pendiente")).font(.system(size: 10, weight: .medium))
                    }.padding(.horizontal, 13).frame(height: 30).background(Color.asterSurface, in: Capsule()).overlay(Capsule().strokeBorder(Color.asterHairlineStrong, lineWidth: 0.5))
                    GlassIconButton(symbol: AsterAppearance(rawValue: appearance)?.symbol ?? "circle.lefthalf.filled", title: "Apariencia") { choosingAppearance = true }
                        .popover(isPresented: $choosingAppearance, arrowEdge: .bottom) { appearancePicker }
                    GlassIconButton(symbol: "gearshape", title: "Ajustes") { navigate("Conexiones") }
                }
            }
        }.padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 14)
    }
    private var appearancePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Apariencia")).font(.system(size: 13, weight: .semibold))
            ForEach(AsterAppearance.allCases, id: \.self) { value in
                Button {
                    withAnimation(AsterMotion.quick(reduceMotion)) { appearance = value.rawValue }
                    choosingAppearance = false
                } label: {
                    HStack(spacing: 10) { Image(systemName: value.symbol).frame(width: 18); Text(L(value.rawValue)); Spacer(); if appearance == value.rawValue { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)) } }.font(.system(size: 12)).padding(9).frame(width: 145).contentShape(Rectangle())
                }.buttonStyle(FluidButtonStyle())
            }
        }.padding(17)
    }
    @ViewBuilder private var pageContent: some View {
        switch store.page {
        case "Proyectos": ProjectsView()
        case "Misiones": missions
        case "Tareas": TaskBoardView()
        case "Actividad": ActivityWorkspaceView()
        case "Ordenador": ComputerWorkspaceView(computer: store.computer)
        case "Memoria": MemoryView()
        case "Bandeja": inbox
        case "Conexiones": SettingsView()
        default: characters
        }
    }
    private func navigate(_ page: String) { withAnimation(AsterMotion.quick(reduceMotion)) { store.page = page } }
    private func select(_ id: String) { withAnimation(AsterMotion.spring(reduceMotion)) { store.select(id) } }
    /// Home: Aster greets the user, says what is waiting for them and offers its modes.
    private var characters: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                greeting
                modes
                suggestions
            }.padding(.horizontal, 22).padding(.top, 4).padding(.bottom, 18).frame(maxWidth: 860, alignment: .leading)
        }.scrollIndicators(.hidden)
    }
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let base = L(hour < 6 || hour >= 21 ? "Buenas noches" : hour < 14 ? "Buenos días" : "Buenas tardes")
        let name = store.settings.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? base : base + ", " + name
    }
    private var greeting: some View {
        HStack(alignment: .center, spacing: 26) {
            AvatarStage(style: store.agent.style, mood: store.mood(for: store.agent.id) == .calm ? store.previewMood : store.mood(for: store.agent.id), dimension: 150)
                .id(store.agent.id).transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
            VStack(alignment: .leading, spacing: 12) {
                Text(greetingText).font(.asterDisplay(36)).tracking(-0.8).lineLimit(2)
                Text(L(store.busy ? "Estoy trabajando en lo que me pediste. Puedes seguir hablándome mientras." : "Cuéntame qué tienes entre manos y lo hacemos juntos."))
                    .font(.system(size: 14)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    let pending = store.state.tasks.filter { !$0.done }.count
                    if store.busy { glance(LF("%d en marcha", store.state.missions.filter { store.isRunning($0.id) }.count), symbol: "sparkle", presence: true) { navigate("Misiones") } }
                    if store.unread > 0 { glance(LF("%d novedades", store.unread), symbol: "tray") { navigate("Bandeja") } }
                    if pending > 0 { glance(LF("%d tareas pendientes", pending), symbol: "checklist") { navigate("Tareas") } }
                    if !store.busy && store.unread == 0 && pending == 0 { glance(L("Todo al día"), symbol: "checkmark", action: nil) }
                }.padding(.top, 2)
            }
            Spacer(minLength: 0)
        }.animation(AsterMotion.spring(reduceMotion), value: store.agent.id)
    }
    /// A small fact about the user's day that opens where it lives.
    private func glance(_ title: String, symbol: String, presence: Bool = false, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            HStack(spacing: 6) { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)); Text(title).font(.system(size: 11.5, weight: .medium)) }
                .foregroundStyle(presence ? Color.asterPollen : Color.primary.opacity(0.8))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(presence ? Color.asterPollenSoft : Color.asterSurface, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.asterHairline, lineWidth: 1))
        }.buttonStyle(FluidButtonStyle()).disabled(action == nil)
    }
    private var modes: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Modos")).font(.asterDisplay(17))
                Spacer()
                Button { customizing = true } label: { Label(L("Personalizar"), systemImage: "paintbrush.pointed").font(.system(size: 11.5, weight: .medium)) }.buttonStyle(.plain).foregroundStyle(Color.asterAccent)
            }
            FlowLayout(spacing: 8) {
                ForEach(Specialist.modeOrder.compactMap { id in store.state.specialists.first { $0.id == id } }) { agent in
                    let selected = store.agent.id == agent.id
                    Button { select(agent.id) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: agent.symbol).font(.system(size: 11, weight: .semibold))
                            Text(agent.mode).font(.asterDisplay(13, weight: .medium))
                        }.foregroundStyle(selected ? Color.asterOnAccent : Color.primary)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(selected ? AnyShapeStyle(Color.asterAccent) : AnyShapeStyle(Color.asterSurface), in: Capsule(style: .continuous))
                            .overlay(Capsule(style: .continuous).strokeBorder(selected ? Color.clear : Color.asterHairlineStrong, lineWidth: 0.5))
                    }.buttonStyle(FluidButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text(L(store.agent.detail)).font(.system(size: 12.5)).foregroundStyle(muted).lineSpacing(4).frame(maxWidth: 560, alignment: .leading)
                .contentTransition(.opacity).animation(AsterMotion.quick(reduceMotion), value: store.agent.id)
        }
    }
    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Para empezar")).font(.asterDisplay(17))
            VStack(spacing: 0) {
                starter("Pensar una idea", detail: "Una pregunta útil y enfoques concretos", symbol: "lightbulb", text: "Ayúdame a explorar una idea. Empieza con una pregunta útil y propón enfoques concretos.")
                Rectangle().fill(Color.asterHairline).frame(height: 1).padding(.leading, 52)
                starter("Crear algo nuevo", detail: "De una dirección a un primer resultado", symbol: "wand.and.stars", text: "Quiero crear algo original. Ayúdame a encontrar una dirección y convertirla en un primer resultado.")
                Rectangle().fill(Color.asterHairline).frame(height: 1).padding(.leading, 52)
                starter("Hacer avanzar un proyecto", detail: "El próximo paso con más impacto, hecho plan", symbol: "arrow.up.forward", text: "Ayúdame a elegir el próximo paso de mayor impacto para uno de mis proyectos y convertirlo en un plan concreto.")
            }.frostedSurface(18)
        }
    }
    private var composer: some View {
        VStack(spacing: 8) {
            if !store.attachments.isEmpty {
                ScrollView(.horizontal) { HStack(spacing: 8) { ForEach(store.attachments) { file in
                    HStack(spacing: 7) { Image(systemName: "doc"); Text(file.name).lineLimit(1); Button { store.removeAttachment(file.id) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .semibold)) }.buttonStyle(.plain).accessibilityLabel(L("Quitar archivo")) }.font(.system(size: 10)).padding(.horizontal, 11).padding(.vertical, 7).liquidSurface(16)
                } } }.scrollIndicators(.hidden)
            }
            HStack(spacing: 13) {
                Button(action: store.attachFiles) { Image(systemName: "plus").font(.system(size: 17, weight: .regular)).foregroundStyle(muted).frame(width: 25, height: 30) }.buttonStyle(FluidButtonStyle()).disabled(store.mainWorking).accessibilityLabel(L("Adjuntar archivos"))
                Image(systemName: "sparkle").font(.system(size: 16)).foregroundStyle(muted).padding(.leading, 3)
                TextField(L(store.page == "Misiones" && store.mission != nil ? "Continúa esta misión…" : "¿Qué vamos a crear hoy?"), text: $draft, axis: .vertical)
                    .lineLimit(1...4).font(.system(size: 13)).textFieldStyle(.plain).focused($composerFocused).onSubmit { submit() }
                Button { if store.mainWorking { store.stop() } else { submit() } } label: {
                    Image(systemName: store.mainWorking ? "stop.fill" : "arrow.up").font(.system(size: 13, weight: .semibold)).frame(width: 32, height: 32)
                        .foregroundStyle(Color.asterOnAccent).background(Color.asterAccent, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }.buttonStyle(FluidButtonStyle()).disabled(!store.mainWorking && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel(L(store.mainWorking ? "Detener misión" : "Enviar misión"))
            }.padding(.horizontal, 15).padding(.vertical, 13).frostedSurface(25)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(composerFocused ? Color.asterAccent.opacity(0.7) : .clear, lineWidth: 1))
                .animation(AsterMotion.quick(reduceMotion), value: composerFocused)
            HStack(spacing: 6) {
                Circle().fill(store.mainWorking ? Color.asterPollen : Color.asterAccent).frame(width: 5, height: 5)
                MonoLabel(store.mainWorking ? L(store.activity) : store.agent.title + " · " + L(store.agent.role), size: 9)
                Spacer()
                Menu {
                    ForEach([("low", "Rápido"), ("medium", "Equilibrado"), ("high", "Profundo")], id: \.0) { value in Button { var settings = store.settings; settings.effort = value.0; store.settings = settings } label: { if store.settings.effort == value.0 { Label(L(value.1), systemImage: "checkmark") } else { Text(L(value.1)) } } }
                } label: { Text(L(["low": "Rápido", "medium": "Equilibrado", "high": "Profundo"][store.settings.effort] ?? "Equilibrado")).font(.system(size: 9)) }.menuStyle(.borderlessButton).frame(width: 90)
            }.padding(.horizontal, 9)
        }.padding(.horizontal, 10).padding(.top, 11).padding(.bottom, 7)
    }
    private func submit() {
        guard !store.mainWorking, store.hasCapacity, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if store.run(draft, fresh: store.page != "Misiones" || store.mission == nil) { draft = "" }
    }
    private func starter(_ title: String, detail: String, symbol: String, text: String) -> some View {
        Button { draft = L(text); composerFocused = true } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.asterAccent).frame(width: 26, height: 26).background(Color.asterAccentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 2) { Text(L(title)).font(.system(size: 13, weight: .medium)); Text(L(detail)).font(.system(size: 11.5)).foregroundStyle(muted) }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.left").font(.system(size: 10, weight: .semibold)).foregroundStyle(muted)
            }.padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
        }.buttonStyle(FluidButtonStyle())
    }
    /// Gold while Aster works on it, green when done, red when it needs the user.
    private func statusColor(_ mission: Mission) -> Color {
        if store.isRunning(mission.id) { return .asterPollen }
        switch mission.status { case "Completada": return .green; case "Fallida", "Necesita revisión", "Por recuperar": return .red; default: return .asterMuted }
    }
    private var filteredMissions: [Mission] {
        store.state.missions.filter { (showArchived ? $0.archived == true : $0.archived != true) && (store.projectFilter == nil || $0.companyID == store.projectFilter) && (missionQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(missionQuery) || $0.messages.contains { $0.text.localizedCaseInsensitiveContains(missionQuery) }) }.sorted { a, b in if (a.pinned ?? false) != (b.pinned ?? false) { return a.pinned == true }; return a.updated > b.updated }
    }
    private var missions: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Button { store.selectedMission = nil; draft = "" } label: { Label(L("Nueva misión"), systemImage: "plus").font(.system(size: 11)) }.glassControl()
                TextField(L("Buscar misiones…"), text: $missionQuery).textFieldStyle(.roundedBorder).font(.system(size: 11))
                Picker(L("Proyecto"), selection: $store.projectFilter) { Text(L("Todas")).tag(nil as UUID?); ForEach(store.companies) { Text($0.name).tag(Optional($0.id)) } }.labelsHidden().font(.system(size: 10))
                Toggle(L("Archivadas"), isOn: $showArchived).toggleStyle(.switch).font(.system(size: 10))
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(filteredMissions) { mission in
                            Button { store.openMission(mission.id); nearBottom = true } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack(spacing: 4) { if mission.pinned == true { Image(systemName: "pin.fill").font(.system(size: 8)) }; Text(mission.title).font(.system(size: 11, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading) }
                                    HStack(spacing: 5) { Circle().fill(statusColor(mission)).frame(width: 6, height: 6); Text(L(mission.status)).font(.system(size: 10)).foregroundStyle(muted) }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(store.selectedMission == mission.id ? Color.asterAccentSoft : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }.buttonStyle(.plain).contextMenu {
                                Button(L("Renombrar")) { renamingMission = mission }
                                Button(L(mission.pinned == true ? "Desfijar" : "Fijar")) { store.pinMission(mission.id) }
                                Button(L(mission.archived == true ? "Restaurar" : "Archivar")) { store.archiveMission(mission.id, archived: mission.archived != true) }.disabled(store.isRunning(mission.id))
                            }
                        }
                    }
                }
            }.padding(14).frame(width: 207).frostedSurface(22).padding(.trailing, 12)
            Rectangle().fill(ink.opacity(0.025)).frame(width: 1)
            if let mission = store.mission {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) { Text(mission.title).font(.system(size: 12, weight: .semibold)).lineLimit(1); HStack(spacing: 5) { Text(L(mission.status)); if let seconds = mission.elapsedSeconds { Text(L("· ") + String(format: "%.0f s", seconds)) }; if let company = store.state.companies.first(where: { $0.id == mission.companyID }) { Text(L("· ") + company.name) } }.font(.system(size: 9)).foregroundStyle(muted) }
                        Spacer()
                        GlassIconButton(symbol: "arrow.clockwise", title: "Recuperar estado y trabajo guardado", action: { store.recover() }).disabled(store.isRunning(mission.id) || !store.hasCapacity || mission.sessionID == nil)
                        GlassIconButton(symbol: "square.and.arrow.up", title: "Exportar conversación", action: store.exportMission)
                        GlassIconButton(symbol: "folder", title: "Cargar archivos creados", action: store.loadArtifacts).disabled(store.isRunning(mission.id) || !store.hasCapacity || mission.sessionID == nil)
                        Menu { Button(L("Renombrar")) { renamingMission = mission }; Button(L(mission.pinned == true ? "Desfijar" : "Fijar")) { store.pinMission(mission.id) }; Button(L(mission.archived == true ? "Restaurar" : "Archivar")) { store.archiveMission(mission.id, archived: mission.archived != true) } } label: { Image(systemName: "ellipsis").frame(width: 25, height: 25) }.menuStyle(.borderlessButton).frame(width: 25).disabled(store.isRunning(mission.id))
                    }.padding(20)
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                ForEach(mission.messages.filter { !$0.text.isEmpty }) { message in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            if message.role != "user" { CompanionAvatar(style: store.state.specialists.first { $0.id == mission.specialistID }?.style ?? AvatarStyle(), mood: .calm, dimension: 18, animateAtRest: false, framesPerSecond: 12).accessibilityHidden(true) }
                                            Text(message.role == "user" ? L("Tú") : (store.state.specialists.first { $0.id == mission.specialistID }?.title ?? "Aster")).font(.asterDisplay(12, weight: .semibold)).foregroundStyle(message.role == "user" ? Color.asterAccentText : Color.primary)
                                            Text(message.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 9)).foregroundStyle(muted)
                                            Spacer()
                                            if message.role == "assistant" { Button { store.speak(message.text, agentID: mission.specialistID) } label: { Image(systemName: store.speaking ? "stop.circle" : "speaker.wave.2").font(.system(size: 10)) }.buttonStyle(.plain).accessibilityLabel(L("Leer en voz alta")) }
                                            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string) } label: { Image(systemName: "doc.on.doc").font(.system(size: 10)) }.buttonStyle(.plain).accessibilityLabel(L("Copiar mensaje"))
                                        }
                                        RichMessage(text: AsterMarkup.display(message.text)).equatable()
                                    }.padding(message.role == "user" ? 16 : 0).background(message.role == "user" ? Color.asterAccentSoft.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                                if !store.isRunning(mission.id), let learned = mission.learned { LearnedNote(facts: learned) { store.forgetLearned($0, in: mission.id) } }
                                if !store.isRunning(mission.id), let steps = mission.suggestions, !steps.isEmpty {
                                    NextSteps(steps: steps, enabled: store.hasCapacity) { step in
                                        if mission.engine == "direct", store.desktopMission(for: mission.specialistID)?.id == mission.id { store.sendDesktop(step, agentID: mission.specialistID) }
                                        else { store.selectedMission = mission.id; store.run(step) }
                                    }.frame(maxWidth: 520, alignment: .leading)
                                }
                                if let error = mission.error {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Label(L("Esta misión necesita atención"), systemImage: "exclamationmark.circle").font(.system(size: 12, weight: .medium))
                                        Text(L(error)).font(.system(size: 12)).foregroundStyle(muted).textSelection(.enabled)
                                        HStack {
                                            Button(L("Recuperar estado"), action: { store.recover() }).disabled(store.isRunning(mission.id) || !store.hasCapacity || mission.sessionID == nil)
                                            if error.contains("facturación") || error.contains("saldo") { let provider: AIProvider = store.settings.usesClaude ? .anthropic : .openai; Link(LF("Revisar cuenta de %@", provider.name), destination: provider.billingURL) }
                                        }.font(.system(size: 11))
                                    }.padding(18).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5))
                                }
                                if store.isRunning(mission.id) { HStack(spacing: 9) { ThinkingDots(); Text(L(store.activity(for: mission.id))).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.asterPollen) } }
                                ForEach(store.artifacts) { artifact in
                                    Button { store.downloadArtifact(artifact) } label: { Label(URL(fileURLWithPath: artifact.path).lastPathComponent, systemImage: "arrow.down.doc") }.glassControl().font(.system(size: 11))
                                }
                                Color.clear.frame(height: 1).id("bottom").background(GeometryReader { geo in Color.clear.preference(key: MessageBottomKey.self, value: geo.frame(in: .named("messages")).minY) })
                            }.padding(.horizontal, 24).padding(.bottom, 24)
                        }.coordinateSpace(name: "messages")
                        .background(GeometryReader { geo in Color.clear.onAppear { messageViewport = geo.size.height }.onChange(of: geo.size.height) { _, size in messageViewport = size } })
                        .onPreferenceChange(MessageBottomKey.self) { bottom in nearBottom = bottom <= messageViewport + 150 }
                        .onChange(of: mission.messages.last?.text) { _, _ in if nearBottom { proxy.scrollTo("bottom", anchor: .bottom) } }
                        .onChange(of: mission.id) { _, _ in nearBottom = true; proxy.scrollTo("bottom", anchor: .bottom) }
                        .overlay(alignment: .bottomTrailing) { if !nearBottom { GlassIconButton(symbol: "arrow.down", title: "Ver lo último") { nearBottom = true; withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }.padding(15) } }
                    }
                }
            } else { empty("sparkle", title: "Una misión, una dirección", detail: "Pide algo concreto. El equipo guarda cada conversación y el estado real de su trabajo.") }
        }
    }
    private var inbox: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack { VStack(alignment: .leading, spacing: 8) { Text(L("El equipo te escribe.")).font(.system(size: 30, weight: .medium)); Text(L("Novedades, propuestas y lo que necesita tu atención.")).font(.system(size: 12)).foregroundStyle(muted) }; Spacer(); Button(L("Revisar ahora")) { Task { await store.scan() } }.glassControl() }
                if store.state.inbox.isEmpty { empty("tray", title: "Todo tranquilo por aquí", detail: "Conecta tu agenda o Apple Mail para recibir novedades. También verás los resultados de las misiones autónomas.") }
                ForEach(store.state.inbox) { note in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { if !note.read { Circle().fill(Color.purple.opacity(0.6)).frame(width: 5, height: 5) }; Text(note.title).font(.system(size: 14, weight: .medium)); Spacer(); Text(note.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 9)).foregroundStyle(muted) }
                        Text(note.text).font(.system(size: 12)).foregroundStyle(muted).lineSpacing(4).textSelection(.enabled)
                        HStack { if let id = note.missionID { Button(L("Abrir misión")) { store.openMission(id); store.markRead(note.id) } }; if !note.read { Button(L("Marcar como leído")) { store.markRead(note.id) } } }.font(.system(size: 10)).glassControl()
                    }.padding(20).frostedSurface(22)
                }
            }.padding(30)
        }
    }
    private func empty(_ icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 16) { Image(systemName: icon).font(.system(size: 27, weight: .light)).foregroundStyle(muted); Text(L(title)).font(.system(size: 20, weight: .medium)); Text(L(detail)).font(.system(size: 12)).foregroundStyle(muted).multilineTextAlignment(.center).lineSpacing(5).frame(maxWidth: 390) }.padding(45).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CustomizeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var agent: Specialist
    @State private var mood: AvatarMood = .calm
    @Namespace private var palette
    let save: (Specialist) -> Void
    init(original: Specialist, save: @escaping (Specialist) -> Void) { _agent = State(initialValue: original); self.save = save }
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) { Text(L("Hazlo tuyo.")).font(.asterDisplay(27)).tracking(-0.7); Text(L("Pequeños detalles. Mucha personalidad.")).font(.system(size: 11)).foregroundStyle(muted) }
                Spacer(); GlassIconButton(symbol: "xmark", title: "Cerrar personalización") { dismiss() }
            }
            VStack(spacing: 0) {
                AvatarStage(style: agent.style, mood: mood, dimension: 166)
                    .id(agent.style.form.rawValue + agent.style.tint.rawValue)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.93)))
                MoodPicker(selection: $mood, tint: Color.asterAccent).padding(.bottom, 15)
            }.frame(maxWidth: .infinity).frostedSurface(26)
            VStack(spacing: 17) {
                HStack { Text(L("Tamaño")).font(.system(size: 12, weight: .medium)); Slider(value: $agent.style.size, in: 80...200).padding(.horizontal, 12); Text("\(Int(agent.style.size))").font(.system(size: 11)).foregroundStyle(muted).monospacedDigit().frame(width: 29) }
                HStack { Toggle(L("Movimiento"), isOn: $agent.style.motion); Spacer(); Toggle(L("Efectos"), isOn: $agent.style.effects) }.font(.system(size: 12)).toggleStyle(.switch)
                TextField(L("Personalidad y forma de hablar"), text: Binding(get: { agent.personality ?? "" }, set: { agent.personality = $0 }), axis: .vertical).lineLimit(1...3).textFieldStyle(.plain).padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10)).font(.system(size: 12))
            }.padding(20).frostedSurface(24)
            HStack(spacing: 6) { Image(systemName: "accessibility"); Text(L("Se adapta a Reducir movimiento y Reducir transparencia.")) }.font(.system(size: 10)).foregroundStyle(muted)
            HStack {
                Button(L("Restablecer")) { withAnimation(AsterMotion.spring(reduceMotion)) { if let original = Specialist.defaults.first(where: { $0.id == agent.id }) { agent = original } } }.buttonStyle(FluidButtonStyle()).font(.system(size: 11)).foregroundStyle(muted)
                Spacer()
                GlassAction(title: "Guardar modo", symbol: "checkmark", prominent: true) {
                    agent.name = agent.name.trimmingCharacters(in: .whitespacesAndNewlines); if !agent.name.isEmpty { save(agent); dismiss() }
                }.disabled(agent.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 500).background(AmbientBackdrop(tint: Color.asterAccent)).foregroundStyle(.primary)
            .animation(AsterMotion.spring(reduceMotion), value: agent.style.form)
            .animation(AsterMotion.spring(reduceMotion), value: agent.style.tint)
    }
}

/// Aster floating on the desktop. Hover opens the quick chat, a click focuses it,
/// dragging moves it, and the mascot shows when it listens, thinks or speaks.
struct FloatingView: View {
    @EnvironmentObject var store: AsterStore
    @AppStorage("AsterAppearance") private var appearance = AsterAppearance.system.rawValue
    @AppStorage("AsterLanguage") private var language = "es"
    var open: () -> Void
    var talk: () -> Void
    var dictate: () -> Void
    var arrange: () -> Void
    var hide: () -> Void
    var moved: () -> Void
    var dragStarted: () -> Void
    var hover: (Bool) -> Void
    private var style: AvatarStyle { store.state.specialists.first { $0.id == "director" }?.style ?? AvatarStyle() }
    var body: some View {
        CompanionAvatar(style: style, mood: store.mood(), dimension: 76, animateAtRest: true, framesPerSecond: 30, restsInBackground: false)
            .overlay(alignment: .topTrailing) {
                if store.unread > 0 { Circle().fill(Color.asterAccent).frame(width: 8, height: 8).overlay(Circle().stroke(Color.asterSurface, lineWidth: 1.5)).padding(.top, 12).padding(.trailing, 12) }
            }
            .frame(width: DesktopCompanions.mascotSize.width, height: DesktopCompanions.mascotSize.height).accessibilityHidden(true)
            .overlay(CompanionInteraction(open: open, talk: talk, dictate: dictate, arrange: arrange, hide: hide, moved: moved, dragStarted: dragStarted, hover: hover))
            .environment(\.locale, Locale(identifier: language))
            .preferredColorScheme(AsterAppearance(rawValue: appearance)?.scheme)
            .help(L("Cursor para hablar · arrastra para mover · doble clic para abrir Aster"))
    }
}

private struct MessageBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
