import Foundation
import XCTest
@testable import Aster
import CryptoKit

final class RemoteTests: XCTestCase {
    static let relay = "ws://127.0.0.1:8787"
    static func check(_ condition: @autoclosure () throws -> Bool, _ text: String, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue((try? condition()) == true, text, file: file, line: line) }
    static func rejects(_ text: String, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) { do { try body(); XCTFail(text, file: file, line: line) } catch {} }
    @MainActor static func waitUntil(_ text: String, _ condition: @escaping () -> Bool) async throws {
        for _ in 0..<100 { if condition() { return }; try await Task.sleep(for: .milliseconds(100)) }
        throw AsterError.message("Timed out: " + text)
    }
    static func relayRunning() async -> Bool {
        var request = URLRequest(url: URL(string: relay.replacingOccurrences(of: "ws://", with: "http://") + "/health")!); request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Private pairing, TLS enforcement, authenticated encryption, wrong-key/tamper/reflection/replay/expiry rejection and durable claims.
    func testPairingCipherAndLedger() throws {
        let pairing = try RemotePairing(relay: Self.relay, name: "Aster Test Mac")
        Self.check(try RemotePairing.parse(pairing.code) == pairing, "QR pairing round trip")
        Self.rejects("Production must reject cleartext") { try pairing.validate(allowLocal: false) }
        for endpoint in ["ws://example.com", "wss://user:pass@example.com", "wss://example.com?token=leak", "file:///tmp/server", "wss://example.com/other"] {
            Self.rejects("Invalid relay endpoint") { _ = try RemotePairing(relay: endpoint, name: "Test") }
        }
        let mac = RemoteCipher(pairing: pairing, role: .mac); var phoneCipher = RemoteCipher(pairing: pairing, role: .phone)
        let packet = try RemotePacket(.hello, "fixture-private-text"); let sealed = try mac.seal(packet)
        Self.check(!sealed.base64EncodedString().contains("fixture-private-text"), "No plaintext envelope")
        let opened = try phoneCipher.open(sealed); Self.check(try opened.decode(String.self) == "fixture-private-text", "Encrypted round trip")
        Self.rejects("Replay rejected") { _ = try phoneCipher.open(sealed) }
        var reflected = RemoteCipher(pairing: pairing, role: .mac)
        Self.rejects("Reflection rejected") { _ = try reflected.open(sealed) }
        var wrong = RemoteCipher(pairing: try RemotePairing(relay: pairing.relay, name: "Other"), role: .phone)
        Self.rejects("Wrong pairing rejected") { _ = try wrong.open(sealed) }
        var altered = sealed; altered[altered.count - 1] ^= 1
        Self.rejects("Tamper rejected") { _ = try phoneCipher.open(altered) }
        var old = try RemotePacket(.hello, "expired"); old.sentAt = Date().addingTimeInterval(-100)
        Self.rejects("Expired envelope rejected") { _ = try phoneCipher.open(mac.seal(old)) }
        let command = RemoteCommand(operation: .chat, text: "Fixture task", agentID: "study")
        var ledger = RemoteLedger(); Self.check(try ledger.claim(command) == nil, "First command claimed")
        ledger = try JSONDecoder().decode(RemoteLedger.self, from: JSONEncoder().encode(ledger))
        Self.check(try ledger.claim(command)?.status == "received", "Durable uncertain claim blocks replay")
    }

    /// Real WebSocket transport through a local Aster Relay, six-agent snapshot, actual store routing, duplicate delivery,
    /// reconnect and invalid-agent rejection. Needs `pnpm start` in outputs/Aster-Relay; skipped otherwise.
    /// With ASTER_LIVE_ENV_FILE pointing at a private env file it also runs one real OpenAI task and deletes its session.
    @MainActor func testRelayRoundTrip() async throws {
        let relayRunning = await Self.relayRunning()
        try XCTSkipUnless(relayRunning, "Start the local relay first: cd outputs/Aster-Relay && pnpm start")
        let liveFile = ProcessInfo.processInfo.environment["ASTER_LIVE_ENV_FILE"].flatMap { $0.isEmpty ? nil : $0 }
        let pairing = try RemotePairing(relay: Self.relay, name: "Aster Test Mac")
        let command = RemoteCommand(operation: .chat, text: liveFile == nil ? "Fixture task" : "Reply with exactly ASTER_REMOTE_OK. Do not use tools, create files or read anything else.", agentID: "study")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aster-remote-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AsterStore(directory: folder.appendingPathComponent("store"), startServices: false, apiFactory: { if let liveFile { return try AgentAPI(environmentFile: liveFile) }; throw AsterError.message("Offline test fixture; no provider call") })
        store.connectionReady = true; store.page = "Personajes"
        var settings = store.settings; settings.model = "gpt-6-luna"; settings.effort = "low"; settings.useMemory = false; settings.automaticMemory = false; settings.shareSources = false; settings.webSearch = false; settings.delegation = false; settings.maxMinutes = 2; store.settings = settings
        let bridge = MacRemoteBridge(store: store, pairing: pairing, storageDirectory: folder.appendingPathComponent("receipts"), restoresConfiguration: false)
        let phone = RemoteConnection(); var snapshots: [RemoteSnapshot] = []; var receipts: [RemoteReceipt] = []
        phone.onPacket = { packet in
            if packet.kind == .snapshot, let value = try? packet.decode(RemoteSnapshot.self) { snapshots.append(value) }
            if packet.kind == .receipt, let value = try? packet.decode(RemoteReceipt.self) { receipts.append(value) }
        }
        bridge.start(); phone.connect(pairing, role: .phone)
        defer { phone.disconnect(); bridge.stop() }
        try await Self.waitUntil("Real WebSocket handshake", { phone.peerOnline && bridge.connection.peerOnline })
        try await phone.send(.command, RemoteCommand(operation: .snapshot))
        try await Self.waitUntil("Authenticated Mac snapshot", { !snapshots.isEmpty })
        Self.check(snapshots[0].agents.count == 6, "All six real Mac agents shared")
        try await phone.send(.command, command)
        try await Self.waitUntil("Task accepted", { receipts.contains(where: { $0.id == command.id }) })
        Self.check(receipts.last?.status == "accepted" && store.state.missions.count == 1, "Remote command invokes the actual store")
        Self.check(store.page == "Personajes", "Remote task does not steal Mac navigation")
        try await phone.send(.command, command)
        try await Self.waitUntil("Duplicate receipt returned", { receipts.filter { $0.id == command.id }.count == 2 })
        Self.check(store.state.missions.count == 1, "Duplicate command never starts a second task")
        phone.disconnect(); try await Self.waitUntil("Disconnect recognized", { !bridge.connection.peerOnline })
        phone.connect(pairing, role: .phone); try await Self.waitUntil("Reconnect works", { phone.peerOnline })
        try await phone.send(.command, command)
        try await Self.waitUntil("Receipt survives reconnect", { receipts.filter { $0.id == command.id }.count == 3 })
        Self.check(store.state.missions.count == 1, "Reconnect never replays work")
        let invalid = RemoteCommand(operation: .chat, text: "Wrong agent", agentID: "nonexistent")
        try await phone.send(.command, invalid); try await Self.waitUntil("Invalid agent rejected", { receipts.contains(where: { $0.id == invalid.id && $0.status == "error" }) })
        Self.check(store.state.missions.count == 1, "Invalid agent cannot dispatch")
        if let liveFile {
            // Encrypted phone request → local relay → Mac store → OpenAI → confirmed task result; hosted session cleaned up.
            for _ in 0..<600 where store.busy { try await Task.sleep(for: .milliseconds(100)) }
            let result = store.state.missions[0]
            if let session = result.sessionID { _ = try? await AgentAPI(environmentFile: liveFile).json("/" + session, method: "DELETE") }
            Self.check(result.status == "Completada" && result.messages.last?.text.contains("ASTER_REMOTE_OK") == true, "Live remote task must return the requested marker")
        }
    }
}
