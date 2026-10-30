import AppKit
import SwiftUI

struct DesktopChatView: View {
    @ObservedObject var desktop: DesktopCompanions
    /// The floating chat draws its own card; inside the island it sits on the island's black.
    var chrome = true
    @EnvironmentObject var store: AsterStore
    @AppStorage("AsterAppearance") private var appearance = AsterAppearance.system.rawValue
    @AppStorage("AsterLanguage") private var language = "es"
    @State private var following = true
    @State private var scrollHeight: CGFloat = 0
    private var agentID: String { desktop.currentMode }
    private var agent: Specialist { store.state.specialists.first { $0.id == agentID } ?? Specialist.defaults[0] }
    private var modes: [Specialist] { Specialist.modeOrder.compactMap { id in store.state.specialists.first { $0.id == id } } }
    private var style: AvatarStyle { store.state.specialists.first { $0.id == "director" }?.style ?? AvatarStyle() }
    private var mission: Mission? { store.desktopMission(for: agentID) }
    private var working: Bool { store.isRunning(mission?.id) }
    private var recovering: Bool { ["Por recuperar", "Cancelación pendiente"].contains(mission?.status ?? "") }
    private var draft: Binding<String> { Binding(get: { desktop.drafts[agentID] ?? "" }, set: { desktop.setDraft($0, agentID: agentID) }) }
    private var lastAnswer: String { mission?.messages.last(where: { $0.role == "assistant" })?.text ?? "" }
    private var changes: String { "\(mission?.id.uuidString ?? "new")-\(mission?.messages.count ?? 0)-\(lastAnswer.count)" }
    private var status: String {
        switch store.mood(for: agentID) {
        case .listening: return "Escuchando"
        case .speaking: return "Hablando"
        case .thinking: return "Pensando"
        default: return "Listo"
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
            modeBar.padding(.bottom, 10)
            Rectangle().fill(Color.asterHairline).frame(height: 1)
            transcript.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = mission?.error, !error.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(Color.asterAccent)
                    Text(L(error)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
                    Spacer(minLength: 0)
                    if recovering, let id = mission?.id { Button(L("Recuperar")) { store.recover(missionID: id) }.disabled(!store.hasCapacity).glassControl() }
                }.padding(.horizontal, 14).padding(.vertical, 9).background(Color.asterRaised.opacity(0.6))
            }
            if !store.hasCapacity, !working {
                Text(L("Se ha alcanzado el límite de trabajos simultáneos. Tu borrador se conserva.")).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.top, 8)
            }
            if let files = mission?.artifactRecords, !files.isEmpty {
                Button { desktop.expandChat() } label: { Label(LF("%d archivos · abrir conversación", files.count), systemImage: "doc.on.doc").labelStyle(TightLabelStyle()).font(.system(size: 11, weight: .medium)) }
                    .buttonStyle(.plain).foregroundStyle(Color.asterAccent).padding(.horizontal, 14).padding(.top, 8)
            }
            composer.padding(12)
        }
        .modifier(ChatChrome(enabled: chrome, scheme: AsterAppearance(rawValue: appearance)?.scheme))
        .environment(\.locale, Locale(identifier: language))
        .onChange(of: agentID) { _, _ in following = true }
        .onExitCommand { desktop.closeChat() }
    }
    private var header: some View {
        HStack(spacing: 10) {
            CompanionAvatar(style: style, mood: store.mood(for: agentID), dimension: 36, animateAtRest: false, framesPerSecond: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Aster").font(.system(size: 14, weight: .semibold)).tracking(-0.2)
                MonoLabel(agent.mode + " · " + L(status), color: store.mood(for: agentID) == .calm ? .asterMuted : .asterAccent)
            }
            Spacer(minLength: 4)
            icon("plus", "Nueva conversación") { store.newDesktopConversation(agentID: agentID) }.disabled(working)
            icon(desktop.pinned ? "pin.fill" : "pin", desktop.pinned ? "Soltar minichat" : "Fijar minichat") { desktop.togglePin() }
            icon("arrow.up.left.and.arrow.down.right", "Abrir conversación completa") { desktop.expandChat() }
            icon("xmark", "Cerrar minichat") { desktop.closeChat() }
        }
    }
    private var modeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(modes) { mode in ModeChip(title: mode.mode, selected: mode.id == agentID) { desktop.selectMode(mode.id) }.help(L(mode.role)) }
            }.padding(.horizontal, 14)
        }
    }
    private func icon(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11, weight: .medium)).frame(width: 24, height: 24).contentShape(Rectangle()) }
            .buttonStyle(FluidButtonStyle()).foregroundStyle(Color.asterMuted).accessibilityLabel(L(title)).help(L(title))
    }
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if mission?.messages.isEmpty != false {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("¿En qué piensas?")).font(.system(size: 18, weight: .semibold)).tracking(-0.3)
                            Text(L(agent.detail)).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                            VStack(spacing: 0) {
                                ForEach(Array(prompts.enumerated()), id: \.offset) { index, item in
                                    if index > 0 { Rectangle().fill(Color.asterHairline).frame(height: 1) }
                                    Button { desktop.setDraft(L(item.1), agentID: agentID); desktop.focusInput() } label: {
                                        HStack { Text(L(item.0)).font(.system(size: 12)); Spacer(); Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Color.asterMuted) }
                                            .padding(.horizontal, 12).padding(.vertical, 9).contentShape(Rectangle())
                                    }.buttonStyle(FluidButtonStyle())
                                }
                            }.frostedSurface(10).padding(.top, 4)
                        }.padding(.top, 6)
                    }
                    ForEach(mission?.messages ?? []) { message in
                        if !message.text.isEmpty {
                            if message.role == "user" {
                                HStack { Spacer(minLength: 48)
                                    Text(verbatim: message.text).font(.system(size: 13)).lineSpacing(3).textSelection(.enabled)
                                        .padding(.horizontal, 11).padding(.vertical, 8).background(Color.asterRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            } else { RichMessage(text: message.text).equatable().frame(maxWidth: .infinity, alignment: .leading) }
                        }
                    }
                    if working {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.mini)
                            MonoLabel(L(store.activity(for: mission?.id).isEmpty ? "Pensando" : store.activity(for: mission?.id)))
                        }
                    } else if !lastAnswer.isEmpty {
                        HStack(spacing: 14) {
                            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(lastAnswer, forType: .string) } label: { Label(L("Copiar"), systemImage: "doc.on.doc").labelStyle(TightLabelStyle()) }
                            Button { store.speak(lastAnswer, agentID: agentID) } label: { Label(L(store.speaking ? "Detener voz" : "Escuchar"), systemImage: store.speaking ? "stop.fill" : "speaker.wave.2").labelStyle(TightLabelStyle()) }
                        }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Color.asterMuted)
                    }
                    Color.clear.frame(height: 1).id("desktop-bottom").background(GeometryReader { geometry in
                        Color.clear.preference(key: DesktopChatBottomKey.self, value: geometry.frame(in: .named("desktop-scroll")).maxY)
                    })
                }.padding(14)
            }.coordinateSpace(name: "desktop-scroll").background(GeometryReader { geometry in Color.clear.onAppear { scrollHeight = geometry.size.height }.onChange(of: geometry.size.height) { _, value in scrollHeight = value } })
                .onPreferenceChange(DesktopChatBottomKey.self) { bottom in if scrollHeight > 0 { following = bottom <= scrollHeight + 70 } }
                .onChange(of: changes) { _, _ in if following { proxy.scrollTo("desktop-bottom", anchor: .bottom) } }
                .onChange(of: agentID) { _, _ in proxy.scrollTo("desktop-bottom", anchor: .bottom) }
                .overlay(alignment: .bottomTrailing) {
                    if !following { Button { following = true; proxy.scrollTo("desktop-bottom", anchor: .bottom) } label: { Image(systemName: "arrow.down").font(.system(size: 11)).frame(width: 28, height: 28).liquidSurface(14, interactive: true) }.buttonStyle(.plain).accessibilityLabel(L("Ir al último mensaje")).padding(10) }
                }
        }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .bottom, spacing: 6) {
                DesktopComposer(text: draft, placeholder: L("Pregunta a Aster…"), send: { desktop.send() }, close: { desktop.closeChat() }, editing: { desktop.pinned = true })
                    .frame(minHeight: 30, maxHeight: 44).padding(.leading, 4)
                DictationButton(listener: store.listener) { desktop.dictate(agentID) }
                if working {
                    Button { store.stop(missionID: mission?.id) } label: {
                        Image(systemName: "stop.fill").font(.system(size: 10)).frame(width: 30, height: 30).background(Color.asterRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }.buttonStyle(FluidButtonStyle()).accessibilityLabel(L("Detener"))
                } else {
                    let empty = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Button { desktop.send() } label: {
                        Image(systemName: "arrow.up").font(.system(size: 12, weight: .semibold)).frame(width: 30, height: 30)
                            .foregroundStyle(empty ? Color.asterMuted : Color.asterOnAccent)
                            .background(empty ? Color.asterRaised : Color.asterAccent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }.buttonStyle(FluidButtonStyle()).disabled(!store.hasCapacity || recovering || empty)
                        .accessibilityLabel(L("Enviar mensaje a Aster"))
                }
            }.padding(6)
                .background(Color.asterCanvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(store.listener.active ? Color.asterAccent : Color.asterHairlineStrong, lineWidth: store.listener.active ? 1 : 0.5))
            MonoLabel(L("↵ enviar · ⇧↵ línea · ⌥espacio hablar"), size: 9).padding(.leading, 4)
        }
    }
    private var prompts: [(String, String)] {
        switch agentID {
        case "growth": return [("Una campaña", "Ayúdame a preparar una campaña de marketing. Pregúntame lo imprescindible para empezar."), ("Mejorar un texto", "Quiero mejorar un texto de marketing. Ayúdame a hacerlo claro y convincente.")]
        case "builder": return [("Construir una web", "Ayúdame a crear una web. Definamos primero qué tiene que hacer."), ("Resolver un problema", "Ayúdame a resolver un problema técnico paso a paso.")]
        case "strategy": return [("Un plan de negocio", "Ayúdame a preparar un plan de negocio con supuestos claros y próximos pasos."), ("Tomar una decisión", "Ayúdame a comparar mis opciones para tomar una decisión.")]
        case "personal": return [("Ordenar mi día", "Ayúdame a organizar mis prioridades de hoy."), ("Pensar juntos", "Quiero pensar contigo sobre una idea y encontrar un próximo paso.")]
        case "study": return [("Entender una tarea", "Ayúdame a entender una tarea de clase y resolverla paso a paso."), ("Preparar un examen", "Ayúdame a preparar un examen. Hagamos un plan y preguntas de práctica.")]
        default: return [("Pensar una idea", "Ayúdame a desarrollar una idea y convertirla en algo concreto."), ("Mi próximo paso", "Ayúdame a decidir en qué debería centrarme ahora.")]
        }
    }
}

/// The floating chat's card and appearance; the island supplies both itself.
private struct ChatChrome: ViewModifier {
    var enabled: Bool
    var scheme: ColorScheme?
    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.background(Color.asterSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.asterHairlineStrong, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)).padding(1)
                .preferredColorScheme(scheme)
        } else { content }
    }
}

/// Microphone for push-to-talk; it fills with the accent and animates while Aster is listening.
struct DictationButton: View {
    @ObservedObject var listener: VoiceInput
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: listener.active ? "waveform" : "mic").font(.system(size: 12, weight: .medium))
                .symbolEffect(.variableColor.iterative, isActive: listener.phase == .listening)
                .foregroundStyle(listener.active ? Color.asterOnAccent : Color.primary)
                .frame(width: 30, height: 30)
                .background(listener.active ? Color.asterAccent : Color.asterSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(listener.active ? Color.clear : Color.asterHairlineStrong, lineWidth: 0.5))
        }.buttonStyle(FluidButtonStyle())
            .accessibilityLabel(L(listener.active ? "Terminar de dictar" : "Hablar"))
            .help(L(listener.active ? "Terminar de dictar" : "Hablar · ⌥Espacio"))
    }
}

private struct DesktopChatBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct DesktopComposer: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme
    var placeholder: String
    var send: () -> Void
    var close: () -> Void
    var editing: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        let editor = Editor(); editor.isRichText = false; editor.drawsBackground = false; editor.font = .systemFont(ofSize: 13)
        editor.textColor = .labelColor; editor.insertionPointColor = .labelColor; editor.textContainerInset = NSSize(width: 1, height: 5)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false; editor.autoresizingMask = [.width]
        editor.minSize = NSSize(width: 0, height: 42); editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true; editor.delegate = context.coordinator
        editor.onSend = send; editor.onClose = close; editor.onEditing = editing; editor.placeholder = placeholder
        editor.setAccessibilityLabel(placeholder); scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? Editor else { return }
        scroll.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        context.coordinator.parent = self
        if editor.string != text { editor.string = text; editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0)) }
        editor.onSend = send; editor.onClose = close; editor.onEditing = editing; editor.placeholder = placeholder
        editor.textColor = .labelColor; editor.insertionPointColor = .labelColor; editor.setAccessibilityLabel(placeholder); editor.needsDisplay = true
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DesktopComposer
        init(_ parent: DesktopComposer) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let editor = notification.object as? NSTextView { parent.text = editor.string } }
    }
    final class Editor: NSTextView {
        var onSend: () -> Void = {}; var onClose: () -> Void = {}; var onEditing: () -> Void = {}
        var placeholder = ""
        override var needsPanelToBecomeKey: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func becomeFirstResponder() -> Bool { let result = super.becomeFirstResponder(); if result { onEditing() }; return result }
        override func keyDown(with event: NSEvent) {
            if !hasMarkedText(), event.keyCode == 36 || event.keyCode == 76 {
                if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option) { super.keyDown(with: event) } else { onSend() }; return
            }
            if !hasMarkedText(), event.keyCode == 53 { onClose(); return }
            super.keyDown(with: event)
        }
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            if string.isEmpty { (placeholder as NSString).draw(at: NSPoint(x: 6, y: 5), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.placeholderTextColor]) }
        }
    }
}
