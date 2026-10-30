import Foundation
import XCTest
@testable import Aster

/// A recognizer the tests drive by hand; no microphone or speech service is used.
final class FakeSpeechBackend: SpeechBackend {
    var locale: Locale?
    var onText: ((String, Bool) -> Void)?
    var onFailure: ((Error) -> Void)?
    var startError: Error?
    var stopped = false
    var cancelled = false
    func start(locale: Locale, onText: @escaping (String, Bool) -> Void, onFailure: @escaping (Error) -> Void) throws {
        if let startError { throw startError }
        self.locale = locale; self.onText = onText; self.onFailure = onFailure
    }
    func stop() { stopped = true }
    func cancel() { cancelled = true }
}

final class VoiceInputTests: XCTestCase {
    @MainActor static func listener(_ backend: FakeSpeechBackend, authorize: @escaping () async throws -> Void = {}) -> VoiceInput {
        let listener = VoiceInput(makeBackend: { backend }, authorize: authorize)
        listener.silenceTimeout = .milliseconds(60); listener.finalResultTimeout = .milliseconds(60)
        listener.noSpeechTimeout = .milliseconds(150); listener.maximumDuration = .seconds(5)
        return listener
    }
    @MainActor static func settle(_ milliseconds: Int = 30) async throws { try await Task.sleep(for: .milliseconds(milliseconds)) }
    @MainActor static func until(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }

    @MainActor func testWordsAppearAsTheyAreHeardAndSendAfterAPause() async throws {
        let backend = FakeSpeechBackend(), listener = Self.listener(backend)
        var updates: [String] = [], finished: [String] = []
        listener.start(language: "es", onUpdate: { updates.append($0) }, onFinish: { finished.append($0) })
        XCTAssertEqual(listener.phase, .preparing)
        try await Self.until { listener.phase == .listening }
        XCTAssertEqual(backend.locale?.language.languageCode?.identifier, "es")
        backend.onText?("Hola", false); backend.onText?("Hola Aster", false)
        try await Self.until { backend.stopped }
        XCTAssertEqual(updates, ["Hola", "Hola Aster"])
        XCTAssertTrue(backend.stopped, "A pause stops the microphone")
        XCTAssertTrue(finished.isEmpty, "Nothing is sent before the recognizer confirms the words")
        backend.onText?("Hola, Aster.", true)
        try await Self.until { !finished.isEmpty }
        XCTAssertEqual(finished, ["Hola, Aster."])
        XCTAssertEqual(listener.phase, .idle); XCTAssertTrue(backend.cancelled)
    }

    @MainActor func testFinishingEarlyUsesTheLastWordsWhenNoFinalResultArrives() async throws {
        let backend = FakeSpeechBackend(), listener = Self.listener(backend)
        listener.silenceTimeout = .seconds(5)
        var finished: [String] = []
        listener.start(language: "en", onUpdate: { _ in }, onFinish: { finished.append($0) })
        try await Self.until { listener.phase == .listening }
        listener.start(language: "en", onUpdate: { _ in XCTFail("A second start is ignored") }, onFinish: { _ in XCTFail("A second start is ignored") })
        backend.onText?("Remind me tomorrow", false)
        try await Self.settle()
        listener.finish()
        try await Self.until { !finished.isEmpty }
        XCTAssertEqual(finished, ["Remind me tomorrow"])
        backend.onText?("Late words", true)
        try await Self.settle()
        XCTAssertEqual(finished.count, 1, "Results after the dictation ended are ignored")
    }

    @MainActor func testSilenceAndCancelledRecognitionEndQuietly() async throws {
        let backend = FakeSpeechBackend(), listener = Self.listener(backend)
        var errors: [String] = [], finished: [String] = []
        listener.onError = { errors.append($0) }
        listener.start(language: "es", onUpdate: { _ in }, onFinish: { finished.append($0) })
        try await Self.until { listener.phase == .listening }
        try await Self.until { listener.phase == .idle }
        XCTAssertEqual(listener.phase, .idle, "Nobody spoke, so listening stops on its own")
        XCTAssertTrue(errors.isEmpty && finished.isEmpty)

        let second = FakeSpeechBackend(), quiet = Self.listener(second)
        quiet.onError = { errors.append($0) }
        quiet.start(language: "es", onUpdate: { _ in }, onFinish: { finished.append($0) })
        try await Self.until { quiet.phase == .listening }
        second.onFailure?(NSError(domain: "kAFAssistantErrorDomain", code: 1110))
        try await Self.until { quiet.phase == .idle }
        XCTAssertTrue(errors.isEmpty, "No speech detected is not an error for the user")
    }

    @MainActor func testFailuresExplainWhatToDo() async throws {
        var errors: [String] = []
        let denied = Self.listener(FakeSpeechBackend(), authorize: { throw AsterError.message("Permite el micrófono para Aster.") })
        denied.onError = { errors.append($0) }
        denied.start(language: "es", onUpdate: { _ in }, onFinish: { _ in XCTFail("Nothing is heard without permission") })
        try await Self.until { denied.phase == .idle && !errors.isEmpty }
        XCTAssertEqual(errors, ["Permite el micrófono para Aster."])

        let broken = FakeSpeechBackend(); broken.startError = AsterError.message("No se encuentra un micrófono disponible.")
        let noMic = Self.listener(broken); noMic.onError = { errors.append($0) }
        noMic.start(language: "es", onUpdate: { _ in }, onFinish: { _ in })
        try await Self.until { errors.count == 2 }
        XCTAssertEqual(errors.last, "No se encuentra un micrófono disponible."); XCTAssertEqual(noMic.phase, .idle)

        let failing = FakeSpeechBackend(), listener = Self.listener(failing); var finished: [String] = []
        listener.onError = { errors.append($0) }
        listener.start(language: "es", onUpdate: { _ in }, onFinish: { finished.append($0) })
        try await Self.until { listener.phase == .listening }
        failing.onText?("Apunta pan", false); try await Self.settle(10)
        failing.onFailure?(NSError(domain: "Network", code: 1, userInfo: [NSLocalizedDescriptionKey: "offline"]))
        try await Self.until { !finished.isEmpty }
        XCTAssertEqual(finished, ["Apunta pan"], "Words already heard are not lost when recognition fails")

        let empty = FakeSpeechBackend(), silent = Self.listener(empty); silent.onError = { errors.append($0) }
        silent.start(language: "es", onUpdate: { _ in }, onFinish: { _ in })
        try await Self.until { silent.phase == .listening }
        empty.onFailure?(NSError(domain: "Network", code: 1, userInfo: [NSLocalizedDescriptionKey: "offline"]))
        try await Self.until { errors.count == 3 }
        XCTAssertTrue(errors.last?.contains("offline") == true)
    }

    func testDictationLanguageFollowsTheUsersRegion() {
        XCTAssertEqual(VoiceInput.locale(for: "es", current: Locale(identifier: "es_MX")).identifier, "es_MX")
        XCTAssertEqual(VoiceInput.locale(for: "en", current: Locale(identifier: "es_MX")).identifier, "en-US")
        XCTAssertEqual(VoiceInput.locale(for: "ca", current: Locale(identifier: "en_US")).identifier, "ca-ES")
        XCTAssertTrue(VoiceInput.isQuiet(NSError(domain: "kAFAssistantErrorDomain", code: 216)))
        XCTAssertFalse(VoiceInput.isQuiet(NSError(domain: "kAFAssistantErrorDomain", code: 1101)))
    }

    @MainActor func testSpokenQuestionsAreAnsweredAloud() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aster-voice-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let backend = FakeSpeechBackend(), listener = Self.listener(backend)
        let provider = ScriptedChatProvider { request, _, event in event(.text("msg", "Respuesta a " + request.input.components(separatedBy: "USER REQUEST:\n").last!)); return "" }
        let store = AsterStore(directory: folder, startServices: false, apiFactory: { throw AsterError.message("Unused") }, chatFactory: { provider }, listener: listener)
        var spoken: [(String, String)] = []
        store.replySpeaker = { spoken.append(($0, $1)) }
        store.startDictation(onUpdate: { _ in }, onFinish: { heard in store.sendDesktop(heard, agentID: "study", spoken: true) })
        try await Self.until { listener.phase == .listening }
        backend.onText?("¿Qué es una derivada?", true)
        try await Self.until { !spoken.isEmpty }
        XCTAssertEqual(spoken.first?.0, "Respuesta a ¿Qué es una derivada?"); XCTAssertEqual(spoken.first?.1, "study", "The companion who answered speaks")

        store.sendDesktop("Escrito a mano", agentID: "study")
        try await Self.until { !store.busy }
        XCTAssertEqual(spoken.count, 1, "Typed questions are not read aloud")

        store.state.preferences.speakReplies = false
        store.sendDesktop("Hablado sin voz", agentID: "study", spoken: true)
        try await Self.until { !store.busy }
        XCTAssertEqual(spoken.count, 1, "The setting turns spoken answers off")
        XCTAssertEqual(store.dictationLanguage, UserDefaults.standard.string(forKey: "AsterLanguage") ?? "es")
        var settings = store.settings; settings.responseLanguage = "en"; store.settings = settings
        XCTAssertEqual(store.dictationLanguage, "en", "Dictation listens for the chosen answer language")
    }
}
