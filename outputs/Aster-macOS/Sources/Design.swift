import SwiftUI
import AppKit

enum AsterAppearance: String, CaseIterable {
    case system = "Sistema", light = "Claro", dark = "Oscuro"
    var scheme: ColorScheme? { self == .system ? nil : self == .dark ? .dark : .light }
    var symbol: String { self == .system ? "circle.lefthalf.filled" : self == .light ? "sun.max" : "moon" }
}

enum AsterMotion {
    static func spring(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.42, bounce: 0.08) }
    static func quick(_ reduced: Bool) -> Animation? { reduced ? nil : .smooth(duration: 0.18) }
}

// Aster's visual system comes from the flower it is named after: violet petals for the
// interface's ink and actions, the golden centre only where Aster itself is present (its halo,
// what it is doing, what it learned), on a cool lilac paper by day and an indigo night by dark.
// Every color adapts to light and dark appearance.
extension Color {
    private static func adaptive(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        func color(_ hex: UInt32, _ alpha: CGFloat) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight]).map { [.darkAqua, .vibrantDark].contains($0) } == true ? color(dark, darkAlpha) : color(light, lightAlpha)
        })
    }
    /// Petal violet: selection, primary actions and links.
    static let asterAccent = adaptive(0x5B4BD6, 0xB4A9FF)
    static let asterAccentSoft = adaptive(0xECE9FD, 0x3A3170, darkAlpha: 0.6)
    static let asterAccentText = adaptive(0x3A2FA0, 0xE2DDFF)
    static let asterOnAccent = adaptive(0xFFFFFF, 0x17142B)
    /// Pollen gold: Aster's own presence — its halo, live activity and what it learned.
    static let asterPollen = adaptive(0xC98A0E, 0xF2BE4A)
    static let asterPollenSoft = adaptive(0xFBF0D6, 0x4A3810, darkAlpha: 0.55)
    static let asterRing = adaptive(0xE0A526, 0xF2BE4A)
    static let asterCanvas = adaptive(0xF5F4FA, 0x121020)
    static let asterSurface = adaptive(0xFFFFFF, 0x1B1930)
    static let asterRaised = adaptive(0xEDEBF6, 0x262340)
    static let asterHairline = adaptive(0x2A2366, 0xE2DDFF, lightAlpha: 0.08, darkAlpha: 0.08)
    static let asterHairlineStrong = adaptive(0x2A2366, 0xE2DDFF, lightAlpha: 0.15, darkAlpha: 0.16)
    static let asterMuted = adaptive(0x6B6880, 0x9E9AB8)
    /// The mascot's body and eyes keep their brand colors in both appearances.
    static let asterBody = Color(red: 1, green: 1, blue: 1)
    static let asterBodyShade = Color(red: 0.937, green: 0.933, blue: 0.984)
    static let asterInk = Color(red: 0.118, green: 0.106, blue: 0.227)
}

extension Font {
    /// Keyboard shortcuts and other literal keys; everything else is SF Pro.
    static func asterMono(_ size: CGFloat = 10, weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight, design: .monospaced) }
    /// Titles, names and greetings: SF Rounded, the same soft geometry as Aster's face.
    static func asterDisplay(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

/// A quiet sentence-case label for a group, a state or a mode.
struct MonoLabel: View {
    var text: String
    var color: Color = .asterMuted
    var size: CGFloat = 10
    init(_ text: String, color: Color = .asterMuted, size: CGFloat = 10) { self.text = text; self.color = color; self.size = size }
    var body: some View { Text(text).font(.system(size: size + 1.5, weight: .medium)).foregroundStyle(color).lineLimit(1) }
}

struct WindowVibrancy: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// The flat canvas behind every page.
struct AmbientBackdrop: View {
    var tint: Color = .asterAccent
    var body: some View { Color.asterCanvas.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true) }
}

/// Floating controls and chips: a solid surface with a hairline and a soft lift.
private struct LiquidSurface: ViewModifier {
    var radius: CGFloat
    var tint: Color?
    var interactive: Bool
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(radius, 18), style: .continuous)
        content.background(tint.map { AnyShapeStyle($0.opacity(0.14)) } ?? AnyShapeStyle(Color.asterSurface), in: shape)
            .overlay(shape.strokeBorder(Color.asterHairlineStrong, lineWidth: 0.5))
            .shadow(color: Color(red: 0.12, green: 0.08, blue: 0.35).opacity(scheme == .dark ? 0.45 : 0.08), radius: interactive ? 6 : 14, y: interactive ? 1 : 6)
    }
}

/// In-flow cards and panels: a solid surface with a hairline, no shadow. Large panels are
/// rounder than the small items inside them.
private struct FrostedSurface: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(radius, 20), style: .continuous)
        content.background(Color.asterSurface, in: shape).overlay(shape.strokeBorder(Color.asterHairline, lineWidth: 1))
    }
}

/// Text buttons. The prominent variant is the single accent action of a view.
struct AsterButtonStyle: ButtonStyle {
    var prominent = false
    /// The single main action of a page, such as the welcome's.
    var large = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        configuration.label.font(.system(size: large ? 13 : 12, weight: prominent ? .semibold : .medium))
            .padding(.horizontal, large ? 22 : 13).padding(.vertical, large ? 10 : 6)
            .foregroundStyle(prominent ? Color.asterOnAccent : Color.primary)
            .background(prominent ? AnyShapeStyle(Color.asterAccent) : AnyShapeStyle(configuration.isPressed ? Color.asterRaised : Color.asterSurface), in: shape)
            .overlay(shape.strokeBorder(prominent ? Color.clear : Color.asterHairlineStrong, lineWidth: 0.5))
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
    }
}

extension View {
    func liquidSurface(_ radius: CGFloat = 20, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidSurface(radius: radius, tint: tint, interactive: interactive))
    }
    func frostedSurface(_ radius: CGFloat = 22) -> some View { modifier(FrostedSurface(radius: radius)) }
    func liquidID(_ id: String, in namespace: Namespace.ID) -> some View { self }
    func glassControl(prominent: Bool = false) -> some View { buttonStyle(AsterButtonStyle(prominent: prominent)) }
}

struct LiquidGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content
    var body: some View { content() }
}

struct FluidButtonStyle: ButtonStyle {
    var lift: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        FluidButtonBody(configuration: configuration, lift: lift, reduced: reduceMotion, enabled: enabled)
    }
    private struct FluidButtonBody: View {
        let configuration: ButtonStyle.Configuration
        let lift: CGFloat
        let reduced: Bool
        let enabled: Bool
        @State private var hovering = false
        var body: some View {
            configuration.label
                .scaleEffect(reduced ? 1 : configuration.isPressed ? 0.975 : 1)
                .brightness(hovering && enabled && !configuration.isPressed ? 0.02 : 0)
                .opacity(enabled ? 1 : 0.42)
                .animation(AsterMotion.quick(reduced), value: hovering)
                .animation(AsterMotion.quick(reduced), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}

struct GlassAction: View {
    @Environment(\.locale) private var locale
    var title: String
    var symbol: String
    var prominent = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(L(title, language: locale.language.languageCode?.identifier), systemImage: symbol).labelStyle(TightLabelStyle())
        }.buttonStyle(AsterButtonStyle(prominent: prominent))
    }
}

/// Icon and title closer together than the default label, as in compact toolbars.
struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon.font(.system(size: 11, weight: .medium)); configuration.title }
    }
}

struct GlassIconButton: View {
    @Environment(\.locale) private var locale
    var symbol: String
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 30, height: 30)
                .background(Color.asterSurface, in: Circle())
                .overlay(Circle().strokeBorder(Color.asterHairlineStrong, lineWidth: 0.5))
        }.buttonStyle(FluidButtonStyle()).accessibilityLabel(L(title, language: locale.language.languageCode?.identifier)).help(L(title, language: locale.language.languageCode?.identifier))
    }
}

/// A selectable monospaced chip, used for modes and moods.
struct ModeChip: View {
    var title: String
    var selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 4)
                .foregroundStyle(selected ? Color.asterAccentText : Color.asterMuted)
                .background(selected ? Color.asterAccentSoft : Color.clear, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(selected ? Color.clear : Color.asterHairlineStrong, lineWidth: 0.5))
                .contentShape(Rectangle())
        }.buttonStyle(FluidButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct MoodPicker: View {
    @Environment(\.locale) private var locale
    @Binding var selection: AvatarMood
    var tint: Color = .asterAccent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 6) {
            ForEach(AvatarMood.allCases, id: \.self) { mood in
                ModeChip(title: L(mood.rawValue, language: locale.language.languageCode?.identifier), selected: selection == mood) {
                    withAnimation(AsterMotion.spring(reduceMotion)) { selection = mood }
                }
            }
        }
    }
}

/// The large mascot of the home page, standing in its golden halo.
struct AvatarStage: View {
    var style: AvatarStyle
    var mood: AvatarMood
    var dimension: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if style.effects && !reduceTransparency {
                Circle().fill(RadialGradient(colors: [Color.asterPollen.opacity(0.22), Color.asterAccent.opacity(0.06), .clear], center: .center, startRadius: 0, endRadius: dimension * 0.62))
                    .frame(width: dimension * 1.25, height: dimension * 1.25)
            }
            CompanionAvatar(style: style, mood: mood, dimension: dimension, framesPerSecond: 30)
        }.frame(width: dimension * 1.3, height: dimension)
    }
}

/// Aster's proposed next steps under an answer; choosing one asks Aster to do it.
struct NextSteps: View {
    var steps: [String]
    var enabled: Bool
    var choose: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel(L("Siguiente"), size: 9)
            ForEach(steps, id: \.self) { step in
                Button { choose(step) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.turn.down.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.asterAccent)
                        Text(step).font(.system(size: 12)).multilineTextAlignment(.leading).foregroundStyle(Color.primary)
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.asterAccentSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.asterAccent.opacity(0.18), lineWidth: 0.5)).contentShape(Rectangle())
                }.buttonStyle(FluidButtonStyle()).disabled(!enabled)
            }
        }
    }
}

/// What Aster just learned about the user, quietly shown under its answer with a way to undo it.
struct LearnedNote: View {
    var facts: [String]
    var tint: Color = .asterMuted
    var undo: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(facts, id: \.self) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.asterPollen)
                    Text(L("Aster ha aprendido:") + " " + fact).font(.system(size: 10.5)).lineLimit(2)
                    Button(L("Deshacer")) { undo(fact) }.buttonStyle(.plain).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color.asterAccent)
                }.foregroundStyle(tint)
            }
        }.accessibilityElement(children: .contain)
    }
}

/// Lays chips out in rows, wrapping to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices { let size = subviews[index].sizeThatFits(.unspecified); subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size)); x += size.width + spacing }
            y += row.height + spacing
        }
    }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1].indices.append(index); rows[rows.count - 1].width += spacing + size.width; rows[rows.count - 1].height = max(last.height, size.height)
            } else { rows.append(([index], size.width, size.height)) }
        }
        return rows
    }
}
