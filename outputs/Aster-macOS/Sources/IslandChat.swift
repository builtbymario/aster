import AppKit
import SwiftUI

/// The chat inside the island. It opens as a single field and grows only as much as the latest
/// answer needs; the full conversation lives in Aster's main window.
struct IslandChatView: View {
    @ObservedObject var desktop: DesktopCompanions
    @EnvironmentObject var store: AsterStore
    @AppStorage("AsterLanguage") private var language = "es"
    @State private var answerHeight: CGFloat = 0
    static let maximumAnswerHeight: CGFloat = 248
    private var agentID: String { desktop.currentMode }
    private var agent: Specialist { store.state.specialists.first { $0.id == agentID } ?? Specialist.defaults[0] }
    private var modes: [Specialist] { Specialist.modeOrder.compactMap { id in store.state.specialists.first { $0.id == id } } }
    private var style: AvatarStyle { store.state.specialists.first { $0.id == "director" }?.style ?? AvatarStyle() }
    private var mission: Mission? { store.desktopMission(for: agentID) }
    private var working: Bool { store.isRunning(mission?.id) }
    private var draft: Binding<String> { Binding(get: { desktop.drafts[agentID] ?? "" }, set: { desktop.setDraft($0, agentID: agentID) }) }
    private var question: String? { mission?.messages.last { $0.role == "user" }?.text }
    private var answer: String { AsterMarkup.display(mission?.messages.last { $0.role == "assistant" }?.text ?? "") }
    private var modeLabel: String {
        guard agent.id == "director", let id = mission?.activeMode, id != "director", let chosen = store.state.specialists.first(where: { $0.id == id }) else { return agent.mode }
        return agent.mode + " · " + chosen.mode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if question != nil || !answer.isEmpty || working { conversation }
            if let error = mission?.error, !error.isEmpty {
                Label(L(error), systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(3)
            }
            field
        }
        .foregroundStyle(.white)
        .environment(\.locale, Locale(identifier: language))
        .onExitCommand { desktop.closeChat() }
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(question.map { $0.components(separatedBy: "\n\n🖥").first ?? $0 } ?? "").font(.system(size: 12)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                Spacer(minLength: 8)
                icon("plus", "Nueva conversación") { store.newDesktopConversation(agentID: agentID) }.disabled(working)
                icon("arrow.up.left.and.arrow.down.right", "Abrir conversación completa") { desktop.expandChat() }
            }
            if !answer.isEmpty {
                ScrollView {
                    RichMessage(text: answer).equatable().frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        .background(GeometryReader { Color.clear.preference(key: AnswerHeightKey.self, value: $0.size.height) })
                }
                .defaultScrollAnchor(.bottom).scrollIndicators(.never)
                .frame(height: min(max(answerHeight, 16), Self.maximumAnswerHeight))
                .onPreferenceChange(AnswerHeightKey.self) { answerHeight = $0 }
            }
            if working {
                HStack(spacing: 8) {
                    ThinkingDots()
                    MonoLabel(L(store.activity(for: mission?.id).isEmpty ? "Pensando" : store.activity(for: mission?.id)), color: .white.opacity(0.5), size: 9)
                }
            } else if let steps = mission?.suggestions, !steps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(steps, id: \.self) { step in
                            Button { _ = store.sendDesktop(step, agentID: agentID) } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.turn.down.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.asterRing)
                                    Text(step).font(.system(size: 11.5)).lineLimit(1)
                                }.padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Color.white.opacity(0.08), in: Capsule()).overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
                            }.buttonStyle(FluidButtonStyle()).disabled(!store.hasCapacity)
                        }
                    }
                }
            }
        }
    }

    /// One row: Aster and its mode, the field, then screen, voice and send.
    private var field: some View {
        let listening = store.listener.active
        let empty = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .center, spacing: 6) {
            // Menu labels cannot draw custom views on macOS, so Aster sits beside its mode menu.
            CompanionAvatar(style: style, mood: store.mood(for: agentID), dimension: 24, animateAtRest: false, framesPerSecond: 30).accessibilityHidden(true)
            Menu {
                ForEach(modes) { mode in
                    Button { desktop.selectMode(mode.id) } label: { if mode.id == agentID { Label(mode.mode, systemImage: "checkmark") } else { Text(mode.mode) } }
                }
            } label: { MonoLabel(modeLabel, color: Color.asterRing, size: 9) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L("Modo")).padding(.trailing, 2)
            DesktopComposer(text: draft, placeholder: L(listening ? "Te escucho…" : "Pregunta a Aster…"), send: { desktop.send() }, close: { desktop.closeChat() }, editing: { desktop.pinned = true })
                .frame(minHeight: 26, maxHeight: 60)
            round(desktop.shareScreen ? "eye.fill" : "eye", active: desktop.shareScreen, title: "Preguntar sobre mi pantalla") { desktop.shareScreen.toggle() }
            round(listening ? "waveform" : "mic", active: listening, title: listening ? "Terminar de dictar" : "Hablar · ⌥Espacio", animating: store.listener.phase == .listening) { desktop.dictate(agentID) }
            Button { working ? store.stop(missionID: mission?.id) : desktop.send() } label: {
                Image(systemName: working ? "stop.fill" : "arrow.up").font(.system(size: working ? 9 : 12, weight: .bold))
                    .foregroundStyle(working || !empty ? Color.black : Color.white.opacity(0.35)).frame(width: 28, height: 28)
                    .background(working || !empty ? Color.asterRing : Color.white.opacity(0.08), in: Circle())
            }.buttonStyle(FluidButtonStyle()).disabled(!working && (empty || !store.hasCapacity)).accessibilityLabel(L(working ? "Detener" : "Enviar mensaje a Aster"))
        }
        .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 6)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(listening || desktop.shareScreen ? Color.asterRing.opacity(0.8) : Color.white.opacity(0.08), lineWidth: 1))
    }

    private func round(_ symbol: String, active: Bool, title: String, animating: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).symbolEffect(.variableColor.iterative, isActive: animating)
                .foregroundStyle(active ? Color.asterRing : Color.white.opacity(0.6)).frame(width: 26, height: 26).contentShape(Rectangle())
        }.buttonStyle(FluidButtonStyle()).accessibilityLabel(L(title)).help(L(title))
    }
    private func icon(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.45)).frame(width: 20, height: 20).contentShape(Rectangle()) }
            .buttonStyle(FluidButtonStyle()).accessibilityLabel(L(title)).help(L(title))
    }
}

private struct AnswerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct IslandContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
