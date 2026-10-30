import AppKit
import SwiftUI
import XCTest
@testable import Aster

/// Renders design references to PNG for visual review. Runs only when ASTER_SNAPSHOTS names a folder.
final class DesignSnapshotTests: XCTestCase {
    @MainActor static func render<V: View>(_ view: V, named name: String, dark: Bool) throws {
        guard let folder = ProcessInfo.processInfo.environment["ASTER_SNAPSHOTS"], !folder.isEmpty else { throw XCTSkip("Set ASTER_SNAPSHOTS to a folder to render design references.") }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var data: Data?
        appearance.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: view.background(Color.asterCanvas).environment(\.colorScheme, dark ? .dark : .light))
            renderer.scale = 2
            if let image = renderer.cgImage { data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) }
        }
        try XCTUnwrap(data).write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }

    @MainActor func testMascotMoods() throws {
        let grid = HStack(spacing: 18) {
            ForEach(AvatarMood.allCases, id: \.self) { mood in
                VStack(spacing: 6) {
                    CompanionAvatar(style: AvatarStyle(), mood: mood, dimension: 96, animateAtRest: false)
                    MonoLabel(mood.rawValue)
                }
            }
        }.padding(24)
        for dark in [false, true] { try Self.render(grid, named: "mascot-moods", dark: dark) }
    }

    @MainActor func testControls() throws {
        let sample = VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) { ForEach(["General", "Study", "Builder", "Founder"], id: \.self) { ModeChip(title: $0, selected: $0 == "Builder") {} } }
            HStack(spacing: 8) {
                GlassAction(title: "Guardar copia", symbol: "square.and.arrow.up") {}
                GlassAction(title: "Empezar", symbol: "arrow.right", prominent: true) {}
                GlassIconButton(symbol: "mic", title: "Hablar") {}
            }
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel("Builder · pensando")
                Text("Una tarjeta con línea fina").font(.system(size: 13, weight: .medium))
                Text("Superficie sólida, sin sombra, con el acento lavanda reservado a lo importante.").font(.system(size: 12)).foregroundStyle(Color.asterMuted)
            }.padding(14).frame(width: 360, alignment: .leading).frostedSurface()
        }.padding(24)
        for dark in [false, true] { try Self.render(sample, named: "controls", dark: dark) }
    }
}
