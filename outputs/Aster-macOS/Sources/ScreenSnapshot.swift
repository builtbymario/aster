import AppKit
import ScreenCaptureKit

/// A single picture of the screen for a question about it: the display under the pointer,
/// without Aster's own windows or the cursor, sized for the model.
enum ScreenSnapshot {
    @MainActor static func capture(maximumWidth: Int = 1600) async throws -> Data {
        guard MacDesktop.canSee else {
            MacDesktop.requestScreen()
            throw AsterError.message("Permite Grabación de pantalla para Aster en Ajustes del Sistema → Privacidad y seguridad y vuelve a intentarlo.")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let id = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        guard let display = content.displays.first(where: { $0.displayID == id?.uint32Value }) ?? content.displays.first else {
            throw AsterError.message("No se encuentra la pantalla.")
        }
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let config = SCStreamConfiguration()
        let bounds = CGDisplayBounds(display.displayID)
        config.width = min(maximumWidth, Int(bounds.width * 2)); config.height = Int(Double(config.width) * bounds.height / bounds.width)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return try await Task.detached(priority: .userInitiated) {
            guard let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else {
                throw AsterError.message("No se ha podido preparar la captura de pantalla.")
            }
            return jpeg
        }.value
    }
}
