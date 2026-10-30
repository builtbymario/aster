import SwiftUI
import AppKit

enum AvatarForm: String, Codable, CaseIterable { case pebble = "Pebble", pill = "Pill", orbit = "Orbit" }
enum AvatarMood: String, CaseIterable { case calm = "En calma", listening = "Escuchando", thinking = "Pensando", speaking = "Hablando", happy = "Contento", curious = "Curioso" }
enum AvatarTint: String, Codable, CaseIterable {
    case pearl = "Perla", lilac = "Lila", mint = "Menta", peach = "Melocotón", ink = "Tinta"
    var color: Color {
        switch self {
        case .pearl: return Color(red: 0.90, green: 0.90, blue: 0.88)
        case .lilac: return Color(red: 0.76, green: 0.73, blue: 0.96)
        case .mint: return Color(red: 0.67, green: 0.83, blue: 0.77)
        case .peach: return Color(red: 0.97, green: 0.76, blue: 0.64)
        case .ink: return Color(red: 0.22, green: 0.23, blue: 0.29)
        }
    }
    var eyes: Color { self == .ink ? .white : Color(red: 0.19, green: 0.19, blue: 0.25) }
}

struct AvatarStyle: Codable, Equatable {
    var form: AvatarForm = .pebble
    var tint: AvatarTint = .lilac
    var size: Double = 140
    var effects: Bool = true
    var motion: Bool = true
}

private struct GazeMotion {
    var start = CGPoint.zero
    var target = CGPoint.zero
    var changed: Double = 0
    func position(at time: Double) -> CGPoint {
        let blend = 1 - exp(-max(0, time - changed) * 16)
        return CGPoint(x: start.x + (target.x - start.x) * blend, y: start.y + (target.y - start.y) * blend)
    }
    mutating func move(to point: CGPoint) {
        let now = Date().timeIntervalSinceReferenceDate
        start = position(at: now); target = point; changed = now
    }
}

/// Aster: a white body with dark eyes and a luminous lavender ring floating beneath it.
/// Its mood shows in the ring and the eyes: steady when calm, rippling while listening,
/// dashed and turning while thinking, and a waveform while speaking.
struct CompanionAvatar: View {
    var style: AvatarStyle
    var mood: AvatarMood = .calm
    var dimension: CGFloat = 150
    var animateAtRest = true
    var framesPerSecond: Double = 60
    /// Whether the idle animation stops while another app is in front. Panels meant to be seen
    /// from other apps (the floating mascot, the island) keep moving.
    var restsInBackground = true
    @State private var appActive = NSApplication.shared.isActive
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var gaze = GazeMotion()
    @State private var visible = false
    @State private var hovering = false
    @State private var previousMood = AvatarMood.calm
    @State private var moodChanged: Double = 0
    private var animated: Bool { style.motion && !reduceMotion && (animateAtRest && (appActive || !restsInBackground) || hovering || mood != .calm) }
    /// At rest Aster only breathes, glances and blinks, which reads well at a low frame rate and
    /// keeps an idle Mac idle; moods and hover get the full rate.
    private var frameRate: Double { hovering || mood != .calm ? framesPerSecond : min(framesPerSecond, Self.restingFrameRate) }
    static let restingFrameRate: Double = 12
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / frameRate, paused: !animated || !visible)) { timeline in
            let time = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
            let progress = time == 0 || moodChanged == 0 ? 1 : min(1, max(0, (time - moodChanged) / 0.28))
            let blend = progress * progress * (3 - 2 * progress)
            let weight = { (candidate: AvatarMood) -> Double in (previousMood == candidate ? 1 - blend : 0) + (mood == candidate ? blend : 0) }
            let look = time == 0 ? CGPoint.zero : gaze.position(at: time)
            Canvas(rendersAsynchronously: true) { context, size in
                draw(in: &context, size: size, time: time, look: look, happy: weight(.happy), curious: weight(.curious),
                     thinking: weight(.thinking), listening: weight(.listening), speaking: weight(.speaking))
            }
        }
        .frame(width: dimension, height: dimension)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): hovering = true; gaze.move(to: CGPoint(x: (location.x / dimension - 0.5) * 2, y: (location.y / dimension - 0.5) * 2))
            case .ended: hovering = false; gaze.move(to: .zero)
            }
        }
        .onAppear { visible = true; previousMood = mood; appActive = NSApplication.shared.isActive }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in appActive = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in appActive = false }
        .onDisappear { visible = false }
        .background(WindowAnimationVisibility { visible = $0 })
        .onChange(of: mood) { old, _ in previousMood = old; moodChanged = Date().timeIntervalSinceReferenceDate }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aster, \(mood.rawValue)")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double, look: CGPoint,
                      happy: Double, curious: Double, thinking: Double, listening: Double, speaking: Double) {
        let unit = min(size.width, size.height)
        let float = time == 0 ? 0 : sin(time * 1.3) * unit * 0.02
        let breathe = time == 0 ? 0 : sin(time * 1.65) * 0.012
        let center = CGPoint(x: size.width / 2, y: size.height * 0.42 + float)
        let width = unit * 0.60 * (1 + breathe), height = unit * 0.54 * (1 - breathe)
        let body = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)

        // The ring floats a little out of phase with the body.
        let ringCenter = CGPoint(x: size.width / 2, y: size.height * 0.85 + (time == 0 ? 0 : sin(time * 1.3 + 0.9) * unit * 0.01))
        let line = max(1, unit * 0.028)
        func ring(scale: Double) -> Path {
            let w = unit * 0.56 * scale, h = unit * 0.11 * scale
            return Path(ellipseIn: CGRect(x: ringCenter.x - w / 2, y: ringCenter.y - h / 2, width: w, height: h))
        }
        let pulse = time == 0 ? 0 : 0.5 + 0.5 * sin(time * 5)
        let ringScale = 1 + 0.10 * listening * pulse
        let ringOpacity = 1 - speaking * 0.85
        if style.effects { context.stroke(ring(scale: ringScale), with: .color(.asterRing.opacity(0.14 * ringOpacity)), lineWidth: line * 4) }
        if listening > 0 && time > 0 {
            let ripple = (time * 0.9).truncatingRemainder(dividingBy: 1)
            context.stroke(ring(scale: 1 + ripple * 0.45), with: .color(.asterRing.opacity((1 - ripple) * 0.55 * listening)), lineWidth: max(0.75, line * 0.6))
        }
        context.stroke(ring(scale: ringScale), with: .color(.asterRing.opacity((1 - thinking) * ringOpacity)), lineWidth: line)
        if thinking > 0 {
            context.stroke(ring(scale: 1), with: .color(.asterRing.opacity(thinking * ringOpacity)),
                           style: StrokeStyle(lineWidth: line, lineCap: .round, dash: [unit * 0.05, unit * 0.035], dashPhase: time * unit * 0.12))
        }
        if speaking > 0 {
            for index in 0..<5 {
                let level = time == 0 ? 0.5 : abs(sin(time * 7 + Double(index) * 1.3))
                let bar = unit * (0.035 + 0.075 * level)
                let x = ringCenter.x + CGFloat(index - 2) * unit * 0.06
                context.fill(Path(roundedRect: CGRect(x: x - unit * 0.016, y: ringCenter.y - bar / 2, width: unit * 0.032, height: bar), cornerRadius: unit * 0.016),
                             with: .color(.asterRing.opacity(speaking)))
            }
        }

        // Body: brand white in both appearances, with a lavender hairline.
        let shape = Path(roundedRect: body, cornerRadius: height * 0.42, style: .continuous)
        context.fill(shape, with: .linearGradient(Gradient(colors: [.asterBody, .asterBodyShade]), startPoint: CGPoint(x: body.midX, y: body.minY), endPoint: CGPoint(x: body.midX, y: body.maxY)))
        context.stroke(shape, with: .color(Color(red: 0.686, green: 0.663, blue: 0.925).opacity(0.9)), lineWidth: max(0.75, unit * 0.012))

        // Eyes look around, blink, and curve into a smile when happy or speaking.
        let blinkPhase = time.truncatingRemainder(dividingBy: 5.3)
        let blink = time == 0 ? 0 : max(0, 1 - abs(blinkPhase - 5.15) / 0.10)
        let lookX = look.x * unit * 0.03 + (time == 0 ? 0 : sin(time * 0.44) * unit * 0.01) + thinking * unit * 0.02
        let eyeWidth = unit * 0.055
        let eyeHeight = unit * 0.10 * (1 + 0.15 * curious + 0.12 * listening) * (1 - blink * 0.85)
        let smile = max(happy, speaking * 0.8) * (1 - blink)
        for side in [-1.0, 1.0] {
            let x = center.x + CGFloat(side) * unit * 0.105 + lookX
            let y = center.y - unit * 0.01 + look.y * unit * 0.02 - thinking * unit * 0.018
            if smile > 0 {
                var arc = Path()
                arc.move(to: CGPoint(x: x - eyeWidth, y: y + eyeWidth * 0.4))
                arc.addQuadCurve(to: CGPoint(x: x + eyeWidth, y: y + eyeWidth * 0.4), control: CGPoint(x: x, y: y - eyeWidth * 1.1))
                context.stroke(arc, with: .color(.asterInk.opacity(smile)), style: StrokeStyle(lineWidth: unit * 0.026, lineCap: .round))
            }
            if smile < 1 {
                let eye = CGRect(x: x - eyeWidth / 2, y: y - eyeHeight / 2, width: eyeWidth, height: eyeHeight)
                context.fill(Path(roundedRect: eye, cornerRadius: eyeWidth / 2), with: .color(.asterInk.opacity(1 - smile)))
            }
        }
        if thinking > 0 {
            for index in 0..<3 {
                let alpha = time == 0 ? 0.6 : 0.3 + 0.6 * (0.5 + 0.5 * sin(time * 3 - Double(index)))
                let x = center.x + CGFloat(index - 1) * unit * 0.05
                context.fill(Path(ellipseIn: CGRect(x: x - unit * 0.011, y: center.y + unit * 0.125, width: unit * 0.022, height: unit * 0.022)), with: .color(.asterRing.opacity(alpha * thinking)))
            }
        }
    }
}

private struct WindowAnimationVisibility: NSViewRepresentable {
    var changed: (Bool) -> Void
    func makeNSView(context: Context) -> VisibilityView { let view = VisibilityView(); view.changed = changed; return view }
    func updateNSView(_ view: VisibilityView, context: Context) { view.changed = changed }
    final class VisibilityView: NSView {
        var changed: ((Bool) -> Void)?
        private var observer: NSObjectProtocol?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil
            guard let window else { changed?(false); return }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self, weak window] _ in self?.changed?(window?.occlusionState.contains(.visible) == true) }
            DispatchQueue.main.async { [weak self, weak window] in self?.changed?(window?.occlusionState.contains(.visible) == true) }
        }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}

enum AsterGlyph {
    /// Menu bar template: the body with its eyes cut out and the ring floating beneath.
    static func menuBar() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let body = NSBezierPath(roundedRect: NSRect(x: 3.5, y: 2.5, width: 11, height: 9.5), xRadius: 4, yRadius: 4)
            for x in [6.6, 9.8] { body.append(NSBezierPath(roundedRect: NSRect(x: x, y: 5.4, width: 1.6, height: 3.2), xRadius: 0.8, yRadius: 0.8)) }
            body.windingRule = .evenOdd; NSColor.black.setFill(); body.fill()
            let ring = NSBezierPath(ovalIn: NSRect(x: 4, y: 13.6, width: 10, height: 2.6)); ring.lineWidth = 1.2
            NSColor.black.setStroke(); ring.stroke()
            return true
        }
        image.isTemplate = true; image.accessibilityDescription = "Aster"
        return image
    }
}
