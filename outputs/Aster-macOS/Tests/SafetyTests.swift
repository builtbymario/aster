import CoreGraphics
import Foundation
import XCTest
@testable import Aster

/// A Mac whose control under the pointer each test chooses.
final class GuardedDesktop: DesktopBackend {
    var target = ActionTarget(label: "Enviar", appName: "Mail", bundleID: "com.apple.mail")
    var actions: [DesktopAction] = []
    var captures = 0
    let geometry = ScreenGeometry(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800), imageWidth: 1000, imageHeight: 800)
    func capture() async throws -> DesktopFrame { captures += 1; return .init(jpeg: Data("frame-\(captures)".utf8), geometry: geometry, context: "Mail · fixture") }
    @MainActor func perform(_ action: DesktopAction, geometry: ScreenGeometry, allowed: @escaping @MainActor () -> Bool) async throws {
        try action.validate(geometry: geometry, active: allowed()); actions.append(action)
    }
    @MainActor func inspect(_ action: DesktopAction, geometry: ScreenGeometry) -> ActionTarget { target }
}

final class SafetyTests: XCTestCase {
    let mail = ActionTarget(label: "Enviar", appName: "Mail", bundleID: "com.apple.mail")
    let excel = ActionTarget(label: nil, appName: "Excel", bundleID: "com.microsoft.Excel")
    func act(_ kind: String, _ explanation: String = "Paso", text: String? = nil, key: String? = nil, app: String? = nil, sensitive: Bool? = nil) -> DesktopAction {
        DesktopAction(action: kind, explanation: explanation, x: 10, y: 10, text: text, key: key, app: app, sensitive: sensitive)
    }
    func confirms(_ review: ActionReview) -> Bool { if case .confirm = review { return true }; return false }
    func blocks(_ review: ActionReview) -> Bool { if case .block = review { return true }; return false }

    func testControlsThatSendPayOrDeleteNeedPermission() {
        for label in ["Enviar", "ENVÍAR", "Send", "Responder a todos", "Reenviar", "Comprar ahora", "Place order", "Eliminar", "Move to Trash", "Publicar", "Allow", "Aceptar y continuar"] {
            XCTAssertTrue(confirms(ActionPolicy.review(act("click"), target: ActionTarget(label: label, appName: "App"))), label)
        }
        for label in ["Negrita", "Bold", "Postal code", "Environment", "Sendero", "Guardar", "Insertar fila"] {
            XCTAssertEqual(ActionPolicy.review(act("click"), target: ActionTarget(label: label, appName: "App")), .allow, label)
        }
        XCTAssertTrue(confirms(ActionPolicy.review(act("click", "Pulso el botón para comprar las entradas"), target: excel)), "The step's own intent counts too")
        XCTAssertTrue(confirms(ActionPolicy.review(act("click", sensitive: true), target: excel)), "The model can flag a step")
        if case .confirm(let reason) = ActionPolicy.review(act("click"), target: mail) { XCTAssertTrue(reason.contains("Enviar") && reason.contains("Mail")) } else { XCTFail() }
    }

    func testSecretsAreNeverTypedByAster() {
        XCTAssertTrue(blocks(ActionPolicy.review(act("type", text: "4242 4242 4242 4242"), target: excel)), "Card number")
        XCTAssertTrue(blocks(ActionPolicy.review(act("type", text: "Clave: sk-proj-abcdefghijklmnop1234"), target: excel)), "API key")
        XCTAssertTrue(blocks(ActionPolicy.review(act("type", text: "-----BEGIN RSA PRIVATE KEY-----"), target: excel)), "Private key")
        XCTAssertTrue(blocks(ActionPolicy.review(act("type", text: "hunter2"), target: ActionTarget(appName: "Safari", secureField: true))), "Password field")
        XCTAssertEqual(ActionPolicy.review(act("type", text: "4242 4242 4242 4241"), target: excel), .allow, "Numbers that are not cards stay usable")
        XCTAssertEqual(ActionPolicy.review(act("type", text: "Total\t=SUMA(B2:B9)\n"), target: excel), .allow)
        XCTAssertTrue(ActionPolicy.luhn("4111111111111111")); XCTAssertFalse(ActionPolicy.luhn("4111111111111112"))
    }

    func testKeysAndAppsThatCannotBeUndone() {
        let messages = ActionTarget(appName: "Mensajes", bundleID: "com.apple.MobileSMS")
        XCTAssertTrue(confirms(ActionPolicy.review(act("key", key: "return"), target: messages)), "Return sends in messaging apps")
        XCTAssertTrue(confirms(ActionPolicy.review(act("type", text: "Llego en 5\n"), target: ActionTarget(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap"))))
        XCTAssertEqual(ActionPolicy.review(act("key", key: "return"), target: excel), .allow, "Return moves between cells elsewhere")
        XCTAssertTrue(confirms(ActionPolicy.review(act("key", key: "cmd+return"), target: ActionTarget(appName: "Safari", bundleID: "com.apple.Safari"))))
        XCTAssertTrue(confirms(ActionPolicy.review(act("key", key: "cmd+shift+d"), target: mail)), "Send in Mail")
        XCTAssertTrue(confirms(ActionPolicy.review(act("key", key: "cmd+q"), target: excel)))
        XCTAssertTrue(confirms(ActionPolicy.review(act("key", key: "cmd+backspace"), target: ActionTarget(appName: "Finder", bundleID: "com.apple.finder"))))
        XCTAssertTrue(blocks(ActionPolicy.review(act("key", key: "cmd+shift+q"), target: excel)), "Logging out")
        XCTAssertEqual(ActionPolicy.review(act("key", key: "cmd+s"), target: excel), .allow)
        XCTAssertTrue(blocks(ActionPolicy.review(act("open_app", app: "Terminal"), target: excel)))
        XCTAssertTrue(blocks(ActionPolicy.review(act("open_app", app: "Ajustes del Sistema"), target: excel)))
        XCTAssertEqual(ActionPolicy.review(act("open_app", app: "Numbers"), target: excel), .allow)
    }

    // MARK: The computer loop

    @MainActor static func run(_ desktop: GuardedDesktop, remote: Bool = false, first: [String: Any], while waiting: (@MainActor (ComputerController) async throws -> Void)? = nil) async throws -> (ComputerController, [[String: Any]]) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("aster-safety-" + UUID().uuidString)
        try "OPENAI_API_KEY=isolated-fixture\n".write(to: file, atomically: true, encoding: .utf8); defer { try? FileManager.default.removeItem(at: file) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DesktopMockProtocol.self]
        let api = try AgentAPI(environmentFile: file.path, baseURL: "https://aster.test/v1", transport: URLSession(configuration: config))
        var bodies: [[String: Any]] = []
        DesktopMockProtocol.handler = { request in
            bodies.append(try DesktopMockProtocol.body(request))
            return try ComputerTests.response("r\(bodies.count)", action: bodies.count == 1 ? first["action"] as! String : "finish", extra: bodies.count == 1 ? first : ["text": "Hecho."])
        }
        let controller = ComputerController()
        controller.start("Responde al correo", agent: Specialist.defaults[0], settings: .init(), api: api, backend: desktop, needsPermissions: false, remote: remote)
        if let waiting {
            for _ in 0..<250 where controller.confirmation == nil && controller.active { try await Task.sleep(for: .milliseconds(20)) }
            try await waiting(controller)
        }
        for _ in 0..<250 where controller.active { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(controller.active, "The run finishes")
        return (controller, bodies)
    }
    static func secondOutput(_ bodies: [[String: Any]]) -> String {
        ((bodies.last?["input"] as? [[String: Any]])?.first { $0["type"] as? String == "function_call_output" }?["output"] as? String) ?? ""
    }

    @MainActor func testAllowedStepRunsAfterTheUserSaysYes() async throws {
        let desktop = GuardedDesktop()
        let (controller, bodies) = try await Self.run(desktop, first: ["action": "click", "x": 120, "y": 80]) { controller in
            XCTAssertNotNil(controller.confirmation, "Aster pauses on a send button")
            XCTAssertTrue(controller.paused); XCTAssertTrue(desktop.actions.isEmpty, "Nothing happens before the answer")
            controller.resume("sí"); XCTAssertNotNil(controller.confirmation, "Continuing or a remote reply cannot approve")
            controller.approve()
        }
        XCTAssertEqual(desktop.actions.map(\.action), ["click"])
        XCTAssertTrue(Self.secondOutput(bodies).contains("Action posted"))
        XCTAssertNil(controller.confirmation)
    }

    @MainActor func testDeclinedStepNeverRuns() async throws {
        let desktop = GuardedDesktop()
        let (controller, bodies) = try await Self.run(desktop, first: ["action": "click", "x": 120, "y": 80]) { $0.deny() }
        XCTAssertTrue(desktop.actions.isEmpty)
        XCTAssertTrue(Self.secondOutput(bodies).contains("did not allow"), "The model hears the step was declined")
        XCTAssertTrue(controller.steps.contains { $0.action == "denied" })
    }

    @MainActor func testTasksFromTheIPhoneDeclineSensitiveSteps() async throws {
        let desktop = GuardedDesktop()
        let (controller, bodies) = try await Self.run(desktop, remote: true, first: ["action": "click", "x": 120, "y": 80])
        XCTAssertTrue(desktop.actions.isEmpty, "Nobody at the Mac can confirm, so the step is declined")
        XCTAssertNil(controller.confirmation)
        XCTAssertTrue(Self.secondOutput(bodies).contains("did not allow"))
    }

    @MainActor func testBlockedStepsAreNotEvenOffered() async throws {
        let desktop = GuardedDesktop(); desktop.target = ActionTarget(appName: "Safari", bundleID: "com.apple.Safari")
        let (_, bodies) = try await Self.run(desktop, first: ["action": "type", "text": "4242 4242 4242 4242"])
        XCTAssertTrue(desktop.actions.isEmpty)
        XCTAssertTrue(Self.secondOutput(bodies).contains("blocked"))
    }

    @MainActor func testAChangedScreenCancelsAnApprovedStep() async throws {
        let desktop = GuardedDesktop()
        let (_, bodies) = try await Self.run(desktop, first: ["action": "click", "x": 120, "y": 80]) { controller in
            desktop.target.label = "Archivar"
            controller.approve()
        }
        XCTAssertTrue(desktop.actions.isEmpty, "The control under the pointer changed while waiting")
        XCTAssertTrue(Self.secondOutput(bodies).contains("screen changed"))
    }
}
