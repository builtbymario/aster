#if DEBUG
import AppKit
import SwiftUI

/// Design review without touching anyone's data: `ASTER_PREVIEW=1` opens a debug build on a
/// throwaway workspace filled with sample content, with no key, no services and no global
/// shortcut. Adding `ASTER_SNAPSHOTS=<folder>` saves a picture of every page there and quits.
@MainActor enum PreviewSupport {
    static var environment: [String: String] { ProcessInfo.processInfo.environment }
    static var enabled: Bool { environment["ASTER_PREVIEW"] == "1" }
    static var snapshotFolder: String? { environment["ASTER_SNAPSHOTS"].flatMap { $0.isEmpty ? nil : $0 } }
    /// A fresh folder per launch, so a preview never reads or changes the real workspace.
    static func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("aster-preview-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    }

    static func seed(_ store: AsterStore) {
        let now = Date()
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        var settings = store.settings; settings.userName = "Mario"; settings.provider = AIProvider.anthropic.rawValue; store.settings = settings
        store.state.preferences.onboarded = true
        let startup = Company(name: "Apuntia", goal: "Una app de apuntes compartidos para estudiantes universitarios", kind: "startup")
        let degree = Company(name: "Ingeniería Industrial", goal: "Aprobar Cálculo II y Física de primero", kind: "study")
        store.state.companies = [startup, degree]
        let answer = """
        ## Plan de lanzamiento

        He ordenado el trabajo en tres frentes. Lo importante es **validar antes de construir**:

        1. Entrevistar a 15 estudiantes de dos facultades distintas.
        2. Publicar una lista de espera con la propuesta de valor.
        3. Medir cuántos comparten sus propios apuntes en la primera semana.

        - Riesgo principal: que nadie suba contenido.
        - Señal a vigilar: `apuntes subidos / usuario activo`.

        > Con menos de un 20 % de usuarios que suben apuntes, el producto no se sostiene solo.

        | Semana | Objetivo | Métrica |
        | --- | --- | --- |
        | 1 | Entrevistas | 15 hechas |
        | 2 | Lista de espera | 200 altas |
        | 3 | Piloto | 40 apuntes |

        ```swift
        let activation = uploads / max(1, activeUsers)
        ```
        """
        var first = Mission(title: "Plan de lanzamiento de Apuntia", specialistID: "strategy", companyID: startup.id, status: "Completada", updated: ago(0.4))
        first.messages = [.init(role: "user", text: "Prepárame un plan de lanzamiento para las tres próximas semanas.", date: ago(0.5)), .init(role: "assistant", text: answer, date: ago(0.4))]
        first.suggestions = ["Redacta el guion de las entrevistas", "Escribe el texto de la lista de espera", "Convierte el plan en tareas"]
        first.learned = ["Mario prefiere planes por semanas con una métrica cada una"]
        first.pinned = true
        var second = Mission(title: "Repaso de integrales por partes", specialistID: "study", companyID: degree.id, status: "Completada", updated: ago(5))
        second.messages = [.init(role: "user", text: "Explícame la integración por partes con un ejemplo.", date: ago(5.2)), .init(role: "assistant", text: "La idea es deshacer la regla del producto: **∫u·dv = u·v − ∫v·du**. Elige como *u* lo que se simplifica al derivar.", date: ago(5))]
        var third = Mission(title: "Ideas para la newsletter de noviembre", specialistID: "content", status: "Completada", updated: ago(28))
        third.messages = [.init(role: "user", text: "Dame cinco temas para la newsletter.", date: ago(28.2)), .init(role: "assistant", text: "Cinco temas con gancho, del más oportuno al más atemporal…", date: ago(28))]
        var fourth = Mission(title: "Comparativa de precios de baterías", specialistID: "research", status: "Necesita revisión", updated: ago(75))
        fourth.messages = [.init(role: "user", text: "Compara tres proveedores europeos.", date: ago(75.3)), .init(role: "assistant", text: "He encontrado datos de dos proveedores; el tercero no publica precios.", date: ago(75))]
        fourth.error = "Falta un dato para terminar: el tercer proveedor no publica sus precios."
        var fifth = Mission(title: "Presupuesto del viaje a Lisboa", specialistID: "finance", status: "Completada", updated: ago(190))
        fifth.messages = [.init(role: "user", text: "Hazme un presupuesto para cuatro días.", date: ago(190.2)), .init(role: "assistant", text: "Con vuelos, alojamiento y comidas, cuatro días salen por unos 520 €.", date: ago(190))]
        store.state.missions = [first, second, third, fourth, fifth]
        store.state.tasks = [
            .init(title: "Entrevistar a cinco estudiantes de Derecho", companyID: startup.id, specialistID: "research", due: ago(30), missionID: first.id),
            .init(title: "Publicar la lista de espera", companyID: startup.id, specialistID: "growth", due: now.addingTimeInterval(3600)),
            .init(title: "Entregar la práctica de Física", companyID: degree.id, specialistID: "study", due: now.addingTimeInterval(3 * 86400)),
            .init(title: "Renovar el dominio", specialistID: "personal"),
            .init(title: "Elegir nombre para la app", companyID: startup.id, done: true)
        ]
        store.state.inbox = [
            .init(title: "Misión terminada: plan de lanzamiento", text: "El plan está listo, con tres semanas, una métrica por semana y los riesgos principales.", date: ago(0.4), fingerprint: "preview-1", missionID: first.id),
            .init(title: "Mañana: entrega de Física a las 12:00", text: "Tienes la práctica 4 pendiente. ¿Quieres que te prepare un repaso de 30 minutos?", date: ago(3), fingerprint: "preview-2"),
            .init(title: "Tres correos necesitan respuesta", text: "Laura (presupuesto), la universidad (matrícula) y el banco (confirmación).", date: ago(26), read: true, fingerprint: "preview-3")
        ]
        store.state.memories = [
            .init(text: "Estudia primero de Ingeniería Industrial y prefiere explicaciones con un ejemplo resuelto.", learned: true),
            .init(text: "Apuntia: el público son estudiantes universitarios de primer y segundo curso.", companyID: startup.id),
            .init(text: "Le gusta que las respuestas terminen con el siguiente paso concreto.", learned: true)
        ]
        store.connectionReady = true; store.connectionStatus = "Conectado a Claude"
        store.selectedProject = startup.id
    }

    // MARK: Pictures

    /// Every page in light and dark, then the palette and onboarding.
    static func snapshot(window: NSWindow, store: AsterStore, folder: String, showChat: @escaping () -> Void = {}) async {
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let pages = environment["ASTER_SNAPSHOT_PAGES"].map { $0.components(separatedBy: ",") } ?? AsterPage.all.map(\.id)
        // Pictures are taken in both appearances; the user's own choice comes back afterwards.
        let chosen = UserDefaults.standard.string(forKey: "AsterAppearance")
        defer { if let chosen { UserDefaults.standard.set(chosen, forKey: "AsterAppearance") } else { UserDefaults.standard.removeObject(forKey: "AsterAppearance") } }
        for scheme in (environment["ASTER_SNAPSHOT_SCHEMES"] ?? "light,dark").components(separatedBy: ",") {
            UserDefaults.standard.set(scheme == "dark" ? AsterAppearance.dark.rawValue : AsterAppearance.light.rawValue, forKey: "AsterAppearance")
            window.appearance = NSAppearance(named: scheme == "dark" ? .darkAqua : .aqua)
            for page in pages {
                if page == "Misiones" { store.selectedMission = store.state.missions.first?.id }
                store.page = page
                await save(window, folder: folder, name: "\(page)-\(scheme)")
            }
            if pages.contains("Paleta") || environment["ASTER_SNAPSHOT_PAGES"] == nil {
                store.page = "Personajes"; store.paletteOpen = true
                await save(window, folder: folder, name: "Paleta-\(scheme)")
                store.paletteOpen = false
                store.onboarding = true
                await save(window, folder: folder, name: "Bienvenida-\(scheme)")
                store.onboarding = false
            }
        }
        // The quick chat in both presentations: inside the island, then as the floating glass card.
        if environment["ASTER_SNAPSHOT_PAGES"] == nil || pages.contains("Chat") {
            for style in ["island", "floating"] {
                store.applyDesktopStyle?(style); try? await Task.sleep(for: .milliseconds(500))
                showChat(); try? await Task.sleep(for: .milliseconds(900))
                for (index, panel) in NSApplication.shared.windows.filter({ $0 !== window && $0.isVisible && $0.frame.width > 200 }).enumerated() {
                    await save(panel, folder: folder, name: "Chat-\(style)-\(index)")
                }
            }
        }
        await report(window, store: store)
        if let chosen { UserDefaults.standard.set(chosen, forKey: "AsterAppearance") } else { UserDefaults.standard.removeObject(forKey: "AsterAppearance") }
        NSApplication.shared.terminate(nil)
    }
    private static func save(_ window: NSWindow, folder: String, name: String) async {
        try? await Task.sleep(for: .milliseconds(900))
        guard let image = composited(window) ?? cached(window) else { return }
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        try? data?.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
    }
    /// The window as the window server draws it, glass included. The call was removed from the
    /// SDK headers but a process may still picture its own windows without any permission.
    private static func composited(_ window: NSWindow) -> CGImage? {
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let capture = unsafeBitCast(symbol, to: Capture.self)
        // Only this window (1 << 3), ignoring its shadow (1 << 0), at full resolution (1 << 3).
        let image = capture(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0 | 1 << 3)?.takeRetainedValue()
        return (image?.width ?? 0) > 10 ? image : nil
    }
    private static func cached(_ window: NSWindow) -> CGImage? {
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep); return rep.cgImage
    }
    /// Sends real clicks through the window and says whether the interface answered: the
    /// settings button (it sits just under the title bar) and a sidebar row.
    private static func report(_ window: NSWindow, store: AsterStore) async {
        guard let frame = window.contentView?.superview else { return }
        func click(_ x: CGFloat, fromTop y: CGFloat) async {
            let point = NSPoint(x: x, y: frame.bounds.maxY - y)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { window.sendEvent(event) }
                try? await Task.sleep(for: .milliseconds(80))
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        var lines = ""
        store.page = "Personajes"; try? await Task.sleep(for: .milliseconds(500))
        await click(frame.bounds.maxX - 31, fromTop: 10 + MainView.toolbarTop + 19)
        lines += "click on settings button -> page \(store.page)\n"
        store.page = "Personajes"; try? await Task.sleep(for: .milliseconds(500))
        await click(100, fromTop: 264)
        lines += "click on sidebar row -> page \(store.page)\n"
        if let button = window.standardWindowButton(.closeButton), let container = button.superview { lines += "close button \(button.frame) in \(container.frame)\n" }
        FileHandle.standardError.write(Data(lines.utf8))
    }
}
#endif
