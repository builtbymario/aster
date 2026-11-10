import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let muted = Color.asterMuted

/// The pages of the main window. Identifiers are the ones stored and used across the app;
/// `title` is what people read.
enum AsterPage {
    /// The places people use every day; the rest sit below, smaller. Settings live in the toolbar.
    static let main: [(id: String, symbol: String)] = [("Personajes", "house"), ("Proyectos", "folder"), ("Misiones", "bubble.left.and.text.bubble.right"), ("Tareas", "checklist"), ("Bandeja", "tray")]
    static let more: [(id: String, symbol: String)] = [("Actividad", "waveform.path"), ("Ordenador", "cursorarrow.motionlines"), ("Memoria", "brain")]
    static let all = main + more + [("Conexiones", "gearshape")]
    static func title(_ page: String) -> String { ["Personajes": "Inicio", "Conexiones": "Ajustes"][page] ?? page }
    /// Pages that end in the shared composer.
    static func hasComposer(_ page: String) -> Bool { !["Conexiones", "Memoria", "Tareas", "Ordenador", "Actividad", "Proyectos", "Bandeja"].contains(page) }
}

struct MainView: View {
    @EnvironmentObject var store: AsterStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("AsterAppearance") private var appearance = AsterAppearance.system.rawValue
    @AppStorage("AsterLanguage") private var language = "es"
    @AppStorage(AsterAccent.key) private var accent = AsterAccent.aster.rawValue
    @Namespace private var navigationNamespace
    @State private var draft = ""
    @State private var customizing = false
    @State private var renamingMission: Mission?
    @State private var choosingAppearance = false
    @State private var dropping = false
    @FocusState private var composerFocused: Bool
    var showCompanion: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            sidebar
            VStack(spacing: 0) {
                toolbar
                pageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(store.page)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
                if AsterPage.hasComposer(store.page) { composer.transition(.opacity.combined(with: .move(edge: .bottom))) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
        // The layout owns the title bar's strip too: the sidebar's glass runs to the top of the
        // window with the window buttons inside it.
        .ignoresSafeArea()
        .frame(minWidth: 1020, minHeight: 720)
        .background(AmbientBackdrop(tint: Color.asterAccent))
        .foregroundStyle(.primary)
        .tint(Color.asterAccent)
        // Accent colors are resolved by AppKit, so a new accent redraws the window from scratch.
        .id(accent)
        .preferredColorScheme(AsterAppearance(rawValue: appearance)?.scheme)
        .environment(\.locale, Locale(identifier: language))
        .animation(AsterMotion.spring(reduceMotion), value: store.page)
        .sheet(isPresented: $customizing) { CustomizeView(original: store.agent) { store.updateAgent($0) } }
        .sheet(item: $renamingMission) { RenameMissionView(mission: $0) }
        .background(shortcuts)
        .overlay(alignment: .top) { NoticeBanner().padding(.top, 14) }
        .overlay(alignment: .bottom) { ToastHost().padding(.bottom, AsterPage.hasComposer(store.page) ? 112 : 22) }
        .overlay { if store.paletteOpen { CommandPalette(focusComposer: { composerFocused = true }, showCompanion: showCompanion).transition(.opacity) } }
        .animation(AsterMotion.quick(reduceMotion), value: store.paletteOpen)
        .accessibilityHidden(store.onboarding)
        .overlay { if store.onboarding { OnboardingView().transition(.opacity) } }
        .animation(AsterMotion.spring(reduceMotion), value: store.onboarding)
    }

    /// Keyboard shortcuts that belong to the window rather than to a menu.
    private var shortcuts: some View {
        ZStack {
            Button("") { composerFocused = true }.keyboardShortcut("l", modifiers: .command)
            Button("") { store.paletteOpen.toggle() }.keyboardShortcut("k", modifiers: .command)
            ForEach(Array(AsterPage.all.prefix(9).enumerated()), id: \.offset) { index, page in
                Button("") { navigate(page.id) }.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }.hidden().accessibilityHidden(true)
    }

    private func navigate(_ page: String) { withAnimation(AsterMotion.spring(reduceMotion)) { store.page = page } }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                CompanionAvatar(style: store.state.specialists.first { $0.id == "director" }?.style ?? AvatarStyle(), mood: store.mood(), dimension: 32, animateAtRest: false, framesPerSecond: 30)
                Text("aster").font(.asterDisplay(22, weight: .bold)).tracking(-0.4)
            }.padding(.top, 42).padding(.bottom, 16).padding(.horizontal, 6)
            Button { store.paletteOpen = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium))
                    Text(L("Buscar")).font(.system(size: 12))
                    Spacer(minLength: 0)
                    KeyCap("⌘K")
                }.foregroundStyle(muted).padding(.horizontal, 10).frame(height: 30)
                    .background(Color.asterWell, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.asterHairline, lineWidth: 1))
                    .contentShape(Rectangle())
            }.buttonStyle(FluidButtonStyle()).padding(.bottom, 14).accessibilityLabel(L("Buscar o saltar a…"))
            ForEach(AsterPage.main, id: \.id) { item in
                SidebarRow(title: L(AsterPage.title(item.id)), symbol: item.symbol, selected: store.page == item.id, namespace: navigationNamespace,
                           badge: item.id == "Bandeja" && store.unread > 0 ? "\(store.unread)" : nil,
                           working: item.id == "Misiones" && store.busy) { navigate(item.id) }
                    .padding(.bottom, 2)
            }
            if !store.companies.isEmpty {
                HStack { MonoLabel(L("Proyectos"), size: 9); Spacer() }.padding(.top, 16).padding(.bottom, 6).padding(.horizontal, 10)
                ForEach(store.companies.prefix(6)) { project in
                    let open = store.page == "Proyectos" && (store.selectedProject ?? store.companies.first?.id) == project.id
                    Button { store.selectedProject = project.id; navigate("Proyectos") } label: {
                        HStack(spacing: 9) {
                            Image(systemName: project.template.symbol).font(.system(size: 10, weight: .medium)).frame(width: 16).foregroundStyle(open ? Color.asterAccent : muted)
                            Text(project.name).font(.system(size: 11.5, weight: open ? .semibold : .regular)).lineLimit(1)
                            Spacer(minLength: 2)
                            if store.isRunning(store.projectChat(project.id)?.id) { Circle().fill(Color.asterPollen).frame(width: 6, height: 6) }
                        }.foregroundStyle(open ? Color.primary : Color.secondary).frame(height: 26).padding(.horizontal, 10)
                            .hoverFill(8).contentShape(Rectangle())
                    }.buttonStyle(FluidButtonStyle())
                }
            }
            Spacer(minLength: 10)
            ForEach(AsterPage.more, id: \.id) { item in
                SidebarRow(title: L(item.id), symbol: item.symbol, selected: store.page == item.id, namespace: navigationNamespace, compact: true) { navigate(item.id) }
            }
            Rectangle().fill(Color.asterHairline).frame(height: 1).padding(.vertical, 12).padding(.horizontal, 6)
            Button(action: showCompanion) {
                HStack(spacing: 9) {
                    Image(systemName: "macwindow.on.rectangle").font(.system(size: 12)).frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("En tu escritorio")).font(.system(size: 11, weight: .medium))
                        Text(L("Siempre a mano")).font(.system(size: 9.5)).foregroundStyle(muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(muted)
                }.padding(.vertical, 7).padding(.horizontal, 10).hoverFill(10).contentShape(Rectangle())
            }.buttonStyle(FluidButtonStyle()).accessibilityLabel(L("Mostrar compañeros en el escritorio")).padding(.bottom, 10)
        }.padding(.horizontal, 10).frame(width: 204).frame(maxHeight: .infinity)
            .glassChrome(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(L(AsterPage.title(store.page))).font(.asterDisplay(17)).padding(.leading, 8)
                .opacity(store.page == "Personajes" ? 0 : 1).id(store.page).transition(.opacity)
            Spacer()
            LiquidGroup(spacing: 10) {
                HStack(spacing: 8) {
                    ConnectionPill()
                    GlassIconButton(symbol: AsterAppearance(rawValue: appearance)?.symbol ?? "circle.lefthalf.filled", title: "Apariencia", chrome: true) { choosingAppearance = true }
                        .popover(isPresented: $choosingAppearance, arrowEdge: .bottom) { appearancePicker }
                    GlassIconButton(symbol: "gearshape", title: "Ajustes", chrome: true) { navigate("Conexiones") }
                }
            }
        }.padding(.horizontal, 6).frame(height: 38).padding(.top, MainView.toolbarTop).padding(.bottom, 8)
    }
    /// Keeps the toolbar's buttons below the window's title bar, which takes the clicks above it.
    static let toolbarTop: CGFloat = 20

    private var appearancePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Apariencia")).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 9).padding(.bottom, 4)
            ForEach(AsterAppearance.allCases, id: \.self) { value in
                Button {
                    withAnimation(AsterMotion.quick(reduceMotion)) { appearance = value.rawValue }
                    choosingAppearance = false
                } label: {
                    HStack(spacing: 10) { Image(systemName: value.symbol).frame(width: 18); Text(L(value.rawValue)); Spacer(); if appearance == value.rawValue { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.asterAccent) } }
                        .font(.system(size: 12)).padding(.horizontal, 9).padding(.vertical, 7).frame(width: 160).hoverFill(8).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Rectangle().fill(Color.asterHairline).frame(height: 1).padding(.vertical, 6)
            Text(L("Color")).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 9).padding(.bottom, 4)
            AccentPicker().padding(.horizontal, 9)
        }.padding(12)
    }

    @ViewBuilder private var pageContent: some View {
        switch store.page {
        case "Proyectos": ProjectsView()
        case "Misiones": MissionsView(draft: $draft, renaming: $renamingMission)
        case "Tareas": TaskBoardView()
        case "Actividad": ActivityWorkspaceView()
        case "Ordenador": ComputerWorkspaceView(computer: store.computer)
        case "Memoria": MemoryView()
        case "Bandeja": InboxView()
        case "Conexiones": SettingsView()
        default: HomeView(draft: $draft, focusComposer: { composerFocused = true }, customize: { customizing = true })
        }
    }

    // MARK: Composer

    private var composer: some View {
        let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(spacing: 7) {
            if !store.attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(store.attachments) { file in
                            HStack(spacing: 6) {
                                Image(systemName: "doc").font(.system(size: 10)).foregroundStyle(Color.asterAccent)
                                Text(file.name).lineLimit(1)
                                Button { withAnimation(AsterMotion.quick(reduceMotion)) { store.removeAttachment(file.id) } } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(muted) }.buttonStyle(.plain).accessibilityLabel(L("Quitar archivo"))
                            }.font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 6).frostedSurface(12).transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }.padding(.horizontal, 4).padding(.vertical, 3)
                }.scrollIndicators(.hidden)
            }
            HStack(alignment: .bottom, spacing: 10) {
                Button(action: store.attachFiles) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .medium)).foregroundStyle(muted).frame(width: 32, height: 32).hoverFill(Circle()).contentShape(Circle())
                }.buttonStyle(FluidButtonStyle()).disabled(store.mainWorking).accessibilityLabel(L("Adjuntar archivos")).help(L("Adjuntar archivos"))
                TextField(L(store.page == "Misiones" && store.mission != nil ? "Continúa esta misión…" : "¿Qué vamos a crear hoy?"), text: $draft, axis: .vertical)
                    .lineLimit(1...6).font(.system(size: 13.5)).textFieldStyle(.plain).focused($composerFocused).onSubmit { submit() }
                    .padding(.vertical, 7)
                Button { if store.mainWorking { store.stop() } else { submit() } } label: {
                    Image(systemName: store.mainWorking ? "stop.fill" : "arrow.up").font(.system(size: 13, weight: .bold)).frame(width: 32, height: 32)
                        .foregroundStyle(empty && !store.mainWorking ? muted : Color.asterOnAccent)
                        .background(empty && !store.mainWorking ? AnyShapeStyle(Color.asterWell) : AnyShapeStyle(Color.asterAccent), in: Circle())
                        .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(empty && !store.mainWorking ? 0 : 0.22), .clear], startPoint: .top, endPoint: .center)))
                        .shadow(color: Color.asterAccent.opacity(empty && !store.mainWorking ? 0 : 0.35), radius: 8, y: 3)
                        .contentTransition(.symbolEffect(.replace))
                }.buttonStyle(FluidButtonStyle()).disabled(!store.mainWorking && empty).accessibilityLabel(L(store.mainWorking ? "Detener misión" : "Enviar misión"))
                    .animation(AsterMotion.quick(reduceMotion), value: empty)
            }.padding(.leading, 8).padding(.trailing, 9).padding(.vertical, 8)
                .glassChrome(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.asterAccent.opacity(dropping ? 0.9 : composerFocused ? 0.55 : 0), lineWidth: dropping ? 2 : 1))
                .animation(AsterMotion.quick(reduceMotion), value: composerFocused)
                .animation(AsterMotion.quick(reduceMotion), value: dropping)
                .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in drop(providers) }
            HStack(spacing: 6) {
                if store.mainWorking { ThinkingDots() } else { Circle().fill(Color.asterAccent).frame(width: 5, height: 5) }
                MonoLabel(store.mainWorking ? L(store.activity) : store.agent.title + " · " + L(store.agent.role), size: 9)
                Spacer()
                Text(L("↵ enviar · ⇧↵ línea · ⌘K buscar")).font(.system(size: 10)).foregroundStyle(muted.opacity(0.8))
                Menu {
                    ForEach([("low", "Rápido"), ("medium", "Equilibrado"), ("high", "Profundo")], id: \.0) { value in Button { var settings = store.settings; settings.effort = value.0; store.settings = settings } label: { if store.settings.effort == value.0 { Label(L(value.1), systemImage: "checkmark") } else { Text(L(value.1)) } } }
                } label: { Text(L(["low": "Rápido", "medium": "Equilibrado", "high": "Profundo"][store.settings.effort] ?? "Equilibrado")).font(.system(size: 10)) }.menuStyle(.borderlessButton).fixedSize().help(L("Profundidad"))
            }.padding(.horizontal, 14)
        }.padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 4)
            .animation(AsterMotion.spring(reduceMotion), value: store.attachments.count)
    }
    private func submit() {
        guard !store.mainWorking, store.hasCapacity, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if store.run(draft, fresh: store.page != "Misiones" || store.mission == nil) { draft = "" }
    }
    /// Files dropped on the composer are attached like those chosen with the + button.
    private func drop(_ providers: [NSItemProvider]) -> Bool {
        let files = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !files.isEmpty else { return false }
        for provider in files {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                Task { @MainActor in store.attach([url]) }
            }
        }
        return true
    }
}

/// One destination in the sidebar. The selection is a single shape that slides between rows.
private struct SidebarRow: View {
    var title: String
    var symbol: String
    var selected: Bool
    var namespace: Namespace.ID
    var badge: String?
    var working = false
    var compact = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 9 : 11) {
                Image(systemName: symbol).font(.system(size: compact ? 10.5 : 12.5, weight: .medium)).frame(width: 18)
                    .foregroundStyle(selected ? Color.asterAccent : Color.secondary)
                Text(title).font(.system(size: compact ? 11.5 : 12.5, weight: selected ? .semibold : .regular))
                Spacer(minLength: 0)
                if working { ThinkingDots().scaleEffect(0.8) }
                if let badge {
                    Text(badge).font(.system(size: 9.5, weight: .bold, design: .rounded)).padding(.horizontal, 5).frame(minWidth: 18, minHeight: 17)
                        .foregroundStyle(Color.asterInk).background(Color.asterRing, in: Capsule()).transition(.scale.combined(with: .opacity))
                }
            }.padding(.horizontal, 10).frame(height: compact ? 26 : 32)
                .foregroundStyle(selected ? Color.asterAccentText : Color.secondary)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.asterAccentSoft)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.asterAccent.opacity(0.16), lineWidth: 1))
                            .matchedGeometryEffect(id: "navigation", in: namespace)
                    }
                }
                .hoverFill(10, active: selected).contentShape(Rectangle())
        }.buttonStyle(FluidButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Whether Aster can reach its AI right now, as a small glass pill.
private struct ConnectionPill: View {
    @EnvironmentObject var store: AsterStore
    var body: some View {
        let label = store.busy ? "Trabajando" : store.connectionStatus.hasPrefix("Conectado a") ? "Conectado" : store.connectionReady ? "Clave válida" : "Conexión pendiente"
        Button { if !store.connectionReady && !store.busy { store.page = "Conexiones" } else if store.busy { store.page = "Actividad" } } label: {
            HStack(spacing: 7) {
                Circle().fill(store.busy ? Color.asterPollen : store.connectionReady ? Color.green : Color.orange).frame(width: 6, height: 6)
                    .shadow(color: (store.busy ? Color.asterPollen : store.connectionReady ? Color.green : Color.orange).opacity(0.7), radius: 3)
                Text(L(label)).font(.system(size: 10.5, weight: .medium)).contentTransition(.opacity)
            }.padding(.horizontal, 13).frame(height: 30).glassChrome(Capsule(style: .continuous), interactive: true, shadow: false)
        }.buttonStyle(FluidButtonStyle()).help(L(store.connectionStatus))
    }
}

/// The accent swatches, in the appearance popover and in Settings.
struct AccentPicker: View {
    @AppStorage(AsterAccent.key) private var accent = AsterAccent.aster.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 8) {
            ForEach(AsterAccent.allCases) { option in
                Button { withAnimation(AsterMotion.quick(reduceMotion)) { accent = option.rawValue } } label: {
                    Circle().fill(option.swatch).frame(width: 18, height: 18)
                        .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(accent == option.rawValue ? 0.9 : 0), lineWidth: 1.5).padding(-3.5))
                        .padding(3.5)
                }.buttonStyle(FluidButtonStyle()).help(L(option.name)).accessibilityLabel(L(option.name)).accessibilityAddTraits(accent == option.rawValue ? .isSelected : [])
            }
        }
    }
}

/// Something that needs to be read: a failed save, a permission macOS did not grant.
private struct NoticeBanner: View {
    @EnvironmentObject var store: AsterStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            if !store.notice.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 14)).foregroundStyle(Color.orange)
                    Text(L(store.notice)).font(.system(size: 12)).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Button { store.notice = "" } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.asterMuted).frame(width: 22, height: 22).hoverFill(Circle()).contentShape(Circle()) }
                        .buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel(L("Entendido"))
                }.padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 10).frame(maxWidth: 520)
                    .glassChrome(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .accessibilityElement(children: .combine).accessibilityAddTraits(.isStaticText)
            }
        }.animation(AsterMotion.bouncy(reduceMotion), value: store.notice)
    }
}

/// Confirmations that leave on their own, with an undo while they are there.
private struct ToastHost: View {
    @EnvironmentObject var store: AsterStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            if let toast = store.toast {
                HStack(spacing: 10) {
                    Image(systemName: toast.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.asterAccent)
                    Text(toast.text).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    if let undo = toast.undo {
                        Button(L("Deshacer")) { undo(); store.toast = nil }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.asterAccent)
                    }
                }.padding(.horizontal, 16).frame(minHeight: 38)
                    .glassChrome(Capsule(style: .continuous))
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94)))
                    .id(toast.id)
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(toast.undo == nil ? 2.6 : 5))
                        if !Task.isCancelled, store.toast?.id == toast.id { store.toast = nil }
                    }
            }
        }.animation(AsterMotion.bouncy(reduceMotion), value: store.toast?.id)
    }
}

struct CustomizeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var agent: Specialist
    @State private var mood: AvatarMood = .calm
    let save: (Specialist) -> Void
    init(original: Specialist, save: @escaping (Specialist) -> Void) { _agent = State(initialValue: original); self.save = save }
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) { Text(L("Hazlo tuyo.")).font(.asterDisplay(27)).tracking(-0.7); Text(L("Pequeños detalles. Mucha personalidad.")).font(.system(size: 11.5)).foregroundStyle(muted) }
                Spacer(); GlassIconButton(symbol: "xmark", title: "Cerrar personalización") { dismiss() }
            }
            VStack(spacing: 0) {
                AvatarStage(style: agent.style, mood: mood, dimension: 166)
                    .id(agent.style.form.rawValue + agent.style.tint.rawValue)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.93)))
                MoodPicker(selection: $mood, tint: Color.asterAccent).padding(.bottom, 15)
            }.frame(maxWidth: .infinity).frostedSurface(24)
            VStack(spacing: 17) {
                HStack { Text(L("Tamaño")).font(.system(size: 12, weight: .medium)); Slider(value: $agent.style.size, in: 80...200).padding(.horizontal, 12); Text("\(Int(agent.style.size))").font(.system(size: 11)).foregroundStyle(muted).monospacedDigit().frame(width: 29) }
                HStack { Toggle(L("Movimiento"), isOn: $agent.style.motion); Spacer(); Toggle(L("Efectos"), isOn: $agent.style.effects) }.font(.system(size: 12)).toggleStyle(.switch)
                TextField(L("Personalidad y forma de hablar"), text: Binding(get: { agent.personality ?? "" }, set: { agent.personality = $0 }), axis: .vertical).lineLimit(1...3).textFieldStyle(.aster).font(.system(size: 12))
            }.padding(20).frostedSurface(22)
            HStack(spacing: 6) { Image(systemName: "accessibility"); Text(L("Se adapta a Reducir movimiento y Reducir transparencia.")) }.font(.system(size: 10)).foregroundStyle(muted)
            HStack {
                Button(L("Restablecer")) { withAnimation(AsterMotion.spring(reduceMotion)) { if let original = Specialist.defaults.first(where: { $0.id == agent.id }) { agent = original } } }.buttonStyle(FluidButtonStyle()).font(.system(size: 11)).foregroundStyle(muted)
                Spacer()
                GlassAction(title: "Guardar modo", symbol: "checkmark", prominent: true) {
                    agent.name = agent.name.trimmingCharacters(in: .whitespacesAndNewlines); if !agent.name.isEmpty { save(agent); dismiss() }
                }.disabled(agent.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 500).background(AmbientBackdrop(tint: Color.asterAccent, vibrant: false)).foregroundStyle(.primary)
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
