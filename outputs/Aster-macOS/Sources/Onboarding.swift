import SwiftUI
import AppKit

// The first minutes with Aster: who it is, which AI it thinks with (the user's own key),
// how it should address them and where it lives on the Mac.

extension AIProvider {
    /// Models offered in pickers: every Claude model the key lists; OpenAI's text models only.
    static func chatModels(_ models: [String], provider: AIProvider, keeping current: String?) -> [String] {
        let excluded = ["audio", "tts", "transcribe", "realtime", "image", "embedding", "search", "moderation", "dall-e", "whisper", "instruct"]
        var options = provider == .anthropic ? models : models.filter { id in (id.hasPrefix("gpt-") || id.range(of: #"^o\d"#, options: .regularExpression) != nil) && !excluded.contains { id.contains($0) } }
        if let current, !options.contains(current) { options.insert(current, at: 0) }
        return options
    }
    /// The model to start with: the one already chosen if the key can use it, else a sensible default.
    static func preferredModel(_ models: [String], provider: AIProvider, current: String?) -> String? {
        if let current, models.contains(current) { return current }
        if provider == .anthropic { return models.contains(AnthropicAPI.defaultModel) ? AnthropicAPI.defaultModel : models.first }
        let chat = chatModels(models, provider: .openai, keeping: nil)
        return ["gpt-6-astra", "gpt-6.1-sol", "gpt-6-sol"].first(where: chat.contains) ?? chat.first
    }
    /// "claude-opus-5-5" reads as "Claude Opus 5.5"; other ids stay as they are.
    static func label(_ id: String) -> String {
        guard id.hasPrefix("claude-") else { return id }
        let parts = id.components(separatedBy: "-").dropFirst().filter { $0.count < 8 }
        let family = parts.filter { Int($0) == nil }.map { $0.capitalized }.joined(separator: " ")
        let version = parts.filter { Int($0) != nil }.joined(separator: ".")
        return (["Claude", family, version].filter { !$0.isEmpty }).joined(separator: " ")
    }
}

extension AsterStore {
    /// Shown once, to someone who has never connected a key to Aster on this Mac.
    var needsOnboarding: Bool { state.preferences.onboarded != true && !AIProvider.openai.hasKey && !AIProvider.anthropic.hasKey }
    func finishOnboarding() { state.preferences.onboarded = true; save(); onboarding = false }

    /// Checks a key with the provider, keeps it in the Keychain and makes that provider Aster's.
    func connect(_ provider: AIProvider, key: String) async throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw AsterError.message("Pega tu clave de API.") }
        let models = try await provider.models(key: value)
        guard !models.isEmpty else { throw AsterError.message("La cuenta no devuelve ningún modelo disponible.") }
        try CredentialVault.save(Data(value.utf8), account: provider.keyAccount)
        var updated = settings; updated.provider = provider.rawValue
        let model = AIProvider.preferredModel(models, provider: provider, current: provider == .anthropic ? updated.claudeModel : updated.model)
        if provider == .anthropic { updated.claudeModel = model } else if let model { updated.model = model }
        settings = updated
        availableModels = models; connectionReady = true; connectionStatus = "Clave válida · modelo disponible"
    }
    /// Switches the provider; the saved key for it, if any, is checked again.
    func choose(_ provider: AIProvider) {
        guard (settings.usesClaude ? AIProvider.anthropic : .openai) != provider else { return }
        var updated = settings; updated.provider = provider.rawValue; settings = updated
        availableModels = []; connectionReady = false; connectionStatus = provider.hasKey ? "Comprobando…" : "Sin conectar"
        if provider.hasKey { refreshConnection() }
    }
    func chooseModel(_ model: String) {
        var updated = settings
        if updated.usesClaude { updated.claudeModel = model } else { updated.model = model }
        settings = updated; connectionReady = availableModels.contains(model)
        connectionStatus = connectionReady ? "Clave válida · modelo disponible" : "El modelo elegido no está disponible en esta cuenta"
    }
}

struct OnboardingView: View {
    @EnvironmentObject var store: AsterStore
    @AppStorage("AsterLanguage") private var language = "es"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var provider = AIProvider.anthropic
    @State private var key = ""
    @State private var checking = false
    @State private var problem = ""
    @State private var connected = false
    private var style: AvatarStyle { store.state.specialists.first { $0.id == "director" }?.style ?? AvatarStyle() }

    var body: some View {
        ZStack {
            Color.asterCanvas.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 6) { ForEach(0..<4) { index in Capsule().fill(index <= step ? Color.asterAccent : Color.asterHairlineStrong).frame(width: index == step ? 22 : 6, height: 6) } }
                    .padding(.top, 34).accessibilityHidden(true)
                Spacer(minLength: 20)
                Group {
                    switch step {
                    case 0: welcome
                    case 1: brain
                    case 2: you
                    default: ready
                    }
                }
                .frame(maxWidth: 520).transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 24)), removal: .opacity.combined(with: .offset(x: -24))))
                .id(step)
                Spacer(minLength: 20)
            }.padding(.horizontal, 40).padding(.bottom, 36)
        }
        .environment(\.locale, Locale(identifier: language))
    }

    private func advance() { withAnimation(AsterMotion.spring(reduceMotion)) { step += 1 } }

    private var welcome: some View {
        VStack(spacing: 26) {
            CompanionAvatar(style: style, mood: .happy, dimension: 104, framesPerSecond: 30).accessibilityHidden(true)
            VStack(spacing: 10) {
                Text(L("Hola, soy Aster")).font(.system(size: 34, weight: .semibold)).tracking(-1)
                Text(L("Tu compañero de IA en el Mac. Vive en el notch, te escucha y hace el trabajo contigo.")).font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(3)
            }
            VStack(alignment: .leading, spacing: 16) {
                feature("sparkles", "Un chat que elige el modo", "Estudio, código, startups, investigación, finanzas o contenido: Aster cambia solo según lo que pidas.")
                feature("cursorarrow.motionlines", "Actúa en tu Mac", "Abre apps, rellena hojas y escribe documentos. Te pregunta antes de enviar, pagar o borrar.")
                feature("calendar", "Tu día, conectado", "Correo, calendario, notas y recordatorios de Apple, leídos en tu Mac.")
            }.padding(22).frostedSurface(20)
            Button(L("Empezar"), action: advance).buttonStyle(AsterButtonStyle(prominent: true, large: true)).keyboardShortcut(.defaultAction)
        }
    }

    private var brain: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("¿Con qué IA piensa Aster?")).font(.system(size: 28, weight: .semibold)).tracking(-0.8)
                Text(L("Usa tu propia clave de API. Se guarda en el Llavero de este Mac y solo se envía a quien la emitió.")).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(3)
            }
            HStack(spacing: 12) {
                choice(.anthropic, detail: "Chat, misiones, control del Mac y preguntas sobre tu pantalla.")
                choice(.openai, detail: "Todo lo anterior, más misiones en la nube con archivos y voces naturales.")
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SecureField(LF("Clave de API de %@", provider.name), text: $key).textFieldStyle(.roundedBorder).onSubmit(connect).disabled(checking)
                    Button(L(checking ? "Comprobando…" : connected ? "Conectada" : "Conectar"), action: connect).buttonStyle(AsterButtonStyle(prominent: !connected))
                        .disabled(checking || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                HStack {
                    Link(LF("Consigue tu clave en %@", provider == .anthropic ? "console.anthropic.com" : "platform.openai.com"), destination: provider.keysURL).font(.system(size: 11))
                    Spacer()
                    if checking { ProgressView().controlSize(.small) }
                }
                if !problem.isEmpty { Label(problem, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                if connected {
                    ModelPicker().font(.system(size: 12))
                    Text(L("Puedes cambiar de IA o de modelo cuando quieras en Ajustes → Conexiones.")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.padding(18).frostedSurface(18)
            HStack {
                Button(L("Más tarde")) { advance() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button(L("Continuar"), action: advance).buttonStyle(AsterButtonStyle(prominent: true, large: true)).disabled(!connected).keyboardShortcut(.defaultAction)
            }
        }
    }

    private var you: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Un poco sobre ti")).font(.system(size: 28, weight: .semibold)).tracking(-0.8)
                Text(L("Aster lo usa para hablarte como prefieres. Lo puedes cambiar luego en Ajustes.")).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                TextField(L("Cómo quieres que te llame"), text: Binding(get: { store.settings.userName }, set: { value in var updated = store.settings; updated.userName = String(value.prefix(80)); store.settings = updated }))
                    .textFieldStyle(.roundedBorder)
                Picker(L("Idioma de la interfaz"), selection: $language) { ForEach(AsterLanguage.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) } }.pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 8) {
                    Picker(L("Aster en tu Mac"), selection: Binding(get: { store.state.preferences.desktopStyle ?? "island" }, set: { store.applyDesktopStyle?($0) })) {
                        Text(L("Isla dinámica")).tag("island"); Text(L("Mascota flotante")).tag("floating")
                    }.pickerStyle(.segmented)
                    Text(L((store.state.preferences.desktopStyle ?? "island") == "island"
                           ? "Aster vive en el notch: pasa el cursor por encima para abrirlo."
                           : "Aster flota en una esquina del escritorio; haz clic para hablar con él.")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.font(.system(size: 12)).padding(20).frostedSurface(18)
            HStack { Spacer(); Button(L("Continuar"), action: advance).buttonStyle(AsterButtonStyle(prominent: true, large: true)).keyboardShortcut(.defaultAction) }
        }
    }

    private var ready: some View {
        VStack(spacing: 24) {
            CompanionAvatar(style: style, mood: .speaking, dimension: 84, framesPerSecond: 30).accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(store.settings.userName.isEmpty ? L("Todo listo") : LF("Todo listo, %@", store.settings.userName)).font(.system(size: 30, weight: .semibold)).tracking(-0.8)
                Text(L(connected ? "Pregúntale lo que quieras. Así se llega a Aster:" : "Conecta tu IA en Ajustes → Conexiones cuando quieras. Así se llega a Aster:")).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                shortcut("⌥ Espacio", "Habla con Aster desde cualquier app")
                shortcut((store.state.preferences.desktopStyle ?? "island") == "island" ? "Notch" : "Mascota", (store.state.preferences.desktopStyle ?? "island") == "island" ? "Pasa el cursor para abrir el chat" : "Haz clic para abrir el chat")
                shortcut("⌥⌘K", "Aster a tu lado: explica lo que hay en tu pantalla")
            }.padding(22).frostedSurface(20)
            VStack(spacing: 10) {
                Text(L("Opcional: conecta tus apps de Apple")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    connector("Calendario", "calendar", on: store.state.preferences.watchCalendar, action: store.connectCalendar)
                    connector("Notas", "note.text", on: store.state.preferences.watchNotes == true, action: store.connectNotes)
                    connector("Mail", "envelope", on: store.state.preferences.watchMail, action: store.connectMail)
                    connector("Notificaciones", "bell", on: store.state.preferences.notifications, action: store.requestNotifications)
                }
            }
            Button(L("Empezar a usar Aster"), action: store.finishOnboarding).buttonStyle(AsterButtonStyle(prominent: true, large: true)).keyboardShortcut(.defaultAction)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.asterAccent).frame(width: 30, height: 30).background(Color.asterAccentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(L(title)).font(.system(size: 13, weight: .semibold))
                Text(L(detail)).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func choice(_ option: AIProvider, detail: String) -> some View {
        let selected = provider == option
        return Button {
            guard !checking else { return }
            withAnimation(AsterMotion.quick(reduceMotion)) { provider = option; problem = ""; connected = false; key = "" }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(option.name).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Color.asterAccent : Color.asterHairlineStrong)
                }
                MonoLabel(option == .anthropic ? "Anthropic" : "OpenAI", size: 9)
                Text(L(detail)).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(selected ? Color.asterAccentSoft : Color.asterSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? Color.asterAccent : Color.asterHairline, lineWidth: selected ? 1.5 : 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func shortcut(_ keys: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            Text(L(keys)).font(.asterMono(11, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 4).frame(minWidth: 86)
                .background(Color.asterRaised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(L(detail)).font(.system(size: 12))
            Spacer(minLength: 0)
        }
    }
    private func connector(_ title: String, _ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(L(title), systemImage: on ? "checkmark" : symbol).font(.system(size: 11)) }
            .buttonStyle(AsterButtonStyle()).disabled(on)
    }
    private func connect() {
        guard !checking, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        checking = true; problem = ""
        Task {
            do { try await store.connect(provider, key: key); key = ""; withAnimation(AsterMotion.quick(reduceMotion)) { connected = true } }
            catch { problem = error.localizedDescription }
            checking = false
        }
    }
}
