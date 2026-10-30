import AVFoundation
import Combine
import Speech
import Carbon

/// Captures the microphone and turns speech into text, reporting partial and final transcripts.
protocol SpeechBackend: AnyObject {
    func start(locale: Locale, onText: @escaping (String, Bool) -> Void, onFailure: @escaping (Error) -> Void) throws
    /// Stops capturing; the recognizer then delivers its final transcript.
    func stop()
    func cancel()
}

/// Apple's Speech framework. Recognition stays on this Mac whenever the language supports it.
final class AppleSpeechBackend: SpeechBackend {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapped = false

    func start(locale: Locale, onText: @escaping (String, Bool) -> Void, onFailure: @escaping (Error) -> Void) throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw AsterError.message("El dictado no está disponible ahora para este idioma. Comprueba el idioma de las respuestas en Ajustes.")
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AsterError.message("No se encuentra un micrófono disponible.") }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        tapped = true
        engine.prepare()
        try engine.start()
        self.request = request
        task = recognizer.recognitionTask(with: request) { result, error in
            if let result { onText(result.bestTranscription.formattedString, result.isFinal) }
            if let error { onFailure(error) }
        }
    }
    func stop() {
        if engine.isRunning { engine.stop() }
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        request?.endAudio()
    }
    func cancel() { stop(); task?.cancel(); task = nil; request = nil }
}

/// Push-to-talk dictation: start, show the words as they arrive, and finish on request or after a pause.
@MainActor final class VoiceInput: ObservableObject {
    enum Phase: Equatable { case idle, preparing, listening }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = ""
    var silenceTimeout: Duration = .milliseconds(1600)
    var noSpeechTimeout: Duration = .seconds(8)
    var maximumDuration: Duration = .seconds(90)
    var finalResultTimeout: Duration = .milliseconds(1500)
    var onError: ((String) -> Void)?
    private let makeBackend: () -> SpeechBackend
    private let authorize: () async throws -> Void
    private var backend: SpeechBackend?
    private var generation = UUID()
    private var update: ((String) -> Void)?
    private var completion: ((String) -> Void)?
    private var timers: [Task<Void, Never>] = []
    private var silence: Task<Void, Never>?

    init(makeBackend: @escaping () -> SpeechBackend = { AppleSpeechBackend() }, authorize: @escaping () async throws -> Void = VoiceInput.requestPermissions) {
        self.makeBackend = makeBackend; self.authorize = authorize
    }
    var active: Bool { phase != .idle }

    func start(language: String, onUpdate: @escaping (String) -> Void, onFinish: @escaping (String) -> Void) {
        guard phase == .idle else { return }
        let token = UUID(); generation = token
        transcript = ""; phase = .preparing; update = onUpdate; completion = onFinish
        Task { [weak self] in
            guard let self else { return }
            do {
                try await authorize()
                guard generation == token else { return }
                let backend = makeBackend(); self.backend = backend
                try backend.start(locale: Self.locale(for: language),
                                  onText: { [weak self] text, final in Task { @MainActor in self?.received(text, final: final, token: token) } },
                                  onFailure: { [weak self] error in Task { @MainActor in self?.failed(error, token: token) } })
                phase = .listening
                schedule(noSpeechTimeout, token) { $0.transcript.isEmpty ? $0.cancel() : () }
                schedule(maximumDuration, token) { $0.finish() }
            } catch {
                guard generation == token else { return }
                cancel(); onError?(error.localizedDescription)
            }
        }
    }
    /// Stops listening and sends what was said once the recognizer confirms it.
    func finish() {
        switch phase {
        case .idle: return
        case .preparing: cancel()
        case .listening:
            backend?.stop()
            schedule(finalResultTimeout, generation) { $0.deliver() }
        }
    }
    func cancel() {
        generation = UUID(); backend?.cancel(); backend = nil
        for timer in timers { timer.cancel() }; timers = []; silence?.cancel(); silence = nil
        phase = .idle; update = nil; completion = nil
    }
    private func received(_ text: String, final: Bool, token: UUID) {
        guard generation == token else { return }
        transcript = text; update?(text)
        if final { deliver(); return }
        silence?.cancel()
        silence = Task { [weak self, silenceTimeout] in
            do { try await Task.sleep(for: silenceTimeout) } catch { return }
            guard let self, self.generation == token else { return }; self.finish()
        }
    }
    private func failed(_ error: Error, token: UUID) {
        guard generation == token else { return }
        if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { deliver(); return }
        cancel()
        if !Self.isQuiet(error) { onError?("No se ha podido reconocer la voz: " + error.localizedDescription) }
    }
    private func deliver() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines), done = completion
        cancel()
        if !text.isEmpty { done?(text) }
    }
    private func schedule(_ delay: Duration, _ token: UUID, _ action: @escaping @MainActor (VoiceInput) -> Void) {
        timers.append(Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, self.generation == token else { return }; action(self)
        })
    }

    /// "No speech" and cancellation end a dictation without being errors for the user.
    nonisolated static func isQuiet(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == "kAFAssistantErrorDomain" && [203, 216, 301, 1110].contains(error.code)
    }
    /// The user's own region when it speaks that language, otherwise a common one.
    nonisolated static func locale(for language: String, current: Locale = .current) -> Locale {
        if current.language.languageCode?.identifier == language { return current }
        let regions = ["es": "ES", "en": "US", "ca": "ES", "fr": "FR", "de": "DE", "it": "IT", "pt": "PT", "ja": "JP", "zh": "CN"]
        return Locale(identifier: regions[language].map { language + "-" + $0 } ?? language)
    }
    nonisolated static func requestPermissions() async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw AsterError.message("Permite el micrófono para Aster en Ajustes del Sistema → Privacidad y seguridad → Micrófono.")
        }
        let speech = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        guard speech == .authorized else {
            throw AsterError.message("Permite el reconocimiento de voz para Aster en Ajustes del Sistema → Privacidad y seguridad → Reconocimiento de voz.")
        }
    }
}

/// ⌥Space from any app starts or finishes dictation, registered only while enabled in Settings.
@MainActor final class VoiceShortcut {
    static let identifier: UInt32 = 2
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @discardableResult func setEnabled(_ value: Bool) -> Bool {
        guard value else { if let hotKey { UnregisterEventHotKey(hotKey) }; hotKey = nil; return true }
        guard hotKey == nil else { return true }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
                guard let userData, VoiceShortcut.hotKeyID(event) == VoiceShortcut.identifier else { return OSStatus(eventNotHandledErr) }
                let shortcut = Unmanaged<VoiceShortcut>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in shortcut.action() }; return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        }
        return RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), EventHotKeyID(signature: 0x41535452, id: Self.identifier), GetApplicationEventTarget(), 0, &hotKey) == noErr
    }
    /// The identifier a hot key event was registered with.
    nonisolated static func hotKeyID(_ event: EventRef?) -> UInt32? {
        guard let event else { return nil }
        var id = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
        return status == noErr ? id.id : nil
    }
}
