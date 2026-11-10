import SwiftUI
import AppKit

enum AsterAppearance: String, CaseIterable {
    case system = "Sistema", light = "Claro", dark = "Oscuro"
    var scheme: ColorScheme? { self == .system ? nil : self == .dark ? .dark : .light }
    var symbol: String { self == .system ? "circle.lefthalf.filled" : self == .light ? "sun.max" : "moon" }
}

/// One motion language for the whole app: springs that settle without wobbling. Every helper
/// returns nil under Reduce Motion, so state changes simply cut.
enum AsterMotion {
    /// Layout and navigation: selections sliding, panels opening.
    static func spring(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(response: 0.42, dampingFraction: 0.84) }
    /// Hover, press and small state changes.
    static func quick(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(response: 0.26, dampingFraction: 0.86) }
    /// Things that arrive: toasts, the palette, a new card.
    static func bouncy(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(response: 0.46, dampingFraction: 0.72) }
}

/// The accent the interface is tinted with. Aster's own violet is the default; the others are
/// there for people who want their Mac's color, not the flower's.
enum AsterAccent: String, CaseIterable, Identifiable {
    case aster, ocean, rose, mint, amber, graphite
    static let key = "AsterAccent"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .aster: return "Aster"; case .ocean: return "Océano"; case .rose: return "Rosa"
        case .mint: return "Menta"; case .amber: return "Ámbar"; case .graphite: return "Grafito"
        }
    }
    /// (accent, soft fill, text on soft fill), each as light and dark.
    var palette: (accent: (UInt32, UInt32), soft: (UInt32, UInt32), text: (UInt32, UInt32)) {
        switch self {
        case .aster: return ((0x5B4BD6, 0xB4A9FF), (0xECE9FD, 0x3A3170), (0x3A2FA0, 0xE2DDFF))
        case .ocean: return ((0x1E6BF0, 0x8FBBFF), (0xE3EEFE, 0x1C3766), (0x1247A8, 0xD8E6FF))
        case .rose: return ((0xD63B7A, 0xFF9EC4), (0xFDE6EF, 0x66203E), (0x9C1F54, 0xFFD9E8))
        case .mint: return ((0x0B8F72, 0x7FE3C8), (0xDDF5EE, 0x124A3D), (0x0A6B56, 0xD3F6EC))
        case .amber: return ((0xC26A05, 0xFFC069), (0xFCEBD3, 0x5A3A0C), (0x8A4D05, 0xFFE5BD))
        case .graphite: return ((0x3C3C46, 0xD6D6E0), (0xE9E9EE, 0x3A3A44), (0x1E1E26, 0xF0F0F5))
        }
    }
    static var current: AsterAccent { AsterAccent(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .aster }
    var swatch: Color { Color.adaptive(palette.accent.0, palette.accent.1) }
}

// Aster's visual system comes from the flower it is named after: violet petals for the
// interface's ink and actions, the golden centre only where Aster itself is present (its halo,
// what it is doing, what it learned), on a cool lilac paper by day and an indigo night by dark.
// Surfaces are glass: translucent, with a bright upper edge, floating over a soft glow.
// Every color adapts to light and dark appearance.
extension Color {
    fileprivate static func resolved(_ hex: UInt32, _ alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
    fileprivate static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight]).map { [.darkAqua, .vibrantDark].contains($0) } == true
    }
    static func adaptive(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { isDark($0) ? resolved(dark, darkAlpha) : resolved(light, lightAlpha) })
    }
    /// A color that follows the chosen accent as well as the appearance.
    private static func themed(_ pick: @escaping (AsterAccent) -> (UInt32, UInt32), darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let pair = pick(AsterAccent.current)
            return isDark(appearance) ? resolved(pair.1, darkAlpha) : resolved(pair.0, 1)
        })
    }
    /// Petal violet (or the chosen accent): selection, primary actions and links.
    static let asterAccent = themed { $0.palette.accent }
    static let asterAccentSoft = themed({ $0.palette.soft }, darkAlpha: 0.6)
    static let asterAccentText = themed { $0.palette.text }
    static let asterOnAccent = adaptive(0xFFFFFF, 0x17142B)
    /// Pollen gold: Aster's own presence — its halo, live activity and what it learned.
    static let asterPollen = adaptive(0xC98A0E, 0xF2BE4A)
    static let asterPollenSoft = adaptive(0xFBF0D6, 0x4A3810, darkAlpha: 0.55)
    static let asterRing = adaptive(0xE0A526, 0xF2BE4A)
    static let asterCanvas = adaptive(0xF5F4FA, 0x121020)
    /// Opaque surface, for places that must not show what is behind them.
    static let asterSurface = adaptive(0xFFFFFF, 0x1B1930)
    static let asterRaised = adaptive(0xEDEBF6, 0x262340)
    /// The body of a glass card: mostly white by day, a faint lift by night.
    static let asterGlass = adaptive(0xFFFFFF, 0xFFFFFF, lightAlpha: 0.62, darkAlpha: 0.055)
    /// Fields and wells set into a card.
    static let asterWell = adaptive(0x2A2366, 0xFFFFFF, lightAlpha: 0.045, darkAlpha: 0.06)
    static let asterHover = adaptive(0x2A2366, 0xFFFFFF, lightAlpha: 0.055, darkAlpha: 0.075)
    static let asterHairline = adaptive(0x2A2366, 0xE2DDFF, lightAlpha: 0.08, darkAlpha: 0.08)
    static let asterHairlineStrong = adaptive(0x2A2366, 0xE2DDFF, lightAlpha: 0.15, darkAlpha: 0.16)
    static let asterMuted = adaptive(0x6B6880, 0x9E9AB8)
    /// The bright rim along the top of glass, and the dimmer one along the bottom.
    static let asterRimTop = adaptive(0xFFFFFF, 0xFFFFFF, lightAlpha: 0.95, darkAlpha: 0.22)
    static let asterRimBottom = adaptive(0x2A2366, 0xFFFFFF, lightAlpha: 0.10, darkAlpha: 0.04)
    static let asterShadow = adaptive(0x1F1559, 0x000000, lightAlpha: 0.10, darkAlpha: 0.42)
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

/// The desktop behind the window, blurred by the system.
struct WindowVibrancy: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

/// The backdrop behind every page: the blurred desktop, washed with Aster's paper, and three
/// still glows for the glass above to catch. Nothing here animates, so an idle window costs nothing.
struct AmbientBackdrop: View {
    var tint: Color = .asterAccent
    /// Sheets and panels that sit on their own window keep the wash but skip the desktop blur.
    var vibrant = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            if vibrant && !reduceTransparency { WindowVibrancy() }
            Color.asterCanvas.opacity(vibrant && !reduceTransparency ? (scheme == .dark ? 0.80 : 0.84) : 1)
            if !reduceTransparency {
                RadialGradient(colors: [tint.opacity(scheme == .dark ? 0.26 : 0.17), .clear], center: UnitPoint(x: 0.02, y: 0.0), startRadius: 0, endRadius: 640)
                RadialGradient(colors: [Color.asterPollen.opacity(scheme == .dark ? 0.12 : 0.11), .clear], center: UnitPoint(x: 1.0, y: 1.0), startRadius: 0, endRadius: 560)
                RadialGradient(colors: [Color(red: 0.36, green: 0.62, blue: 1).opacity(scheme == .dark ? 0.12 : 0.09), .clear], center: UnitPoint(x: 0.92, y: 0.02), startRadius: 0, endRadius: 480)
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Real Liquid Glass for the layer that floats above content: the sidebar, toolbars, composers
/// and panels. Before macOS 26 it is a system material with the same bright rim. Scrolling
/// content never uses this; cards are `frostedSurface`, which costs no backdrop pass.
private struct GlassChrome<S: InsettableShape>: ViewModifier {
    var shape: S
    var tint: Color?
    var interactive: Bool
    var shadow: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Color.asterSurface), in: shape)
                .overlay(shape.strokeBorder(Color.asterHairlineStrong, lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
                .shadow(color: Color.asterShadow.opacity(shadow ? 0.5 : 0), radius: 18, y: 8)
        } else {
            content.background(tint.map { AnyShapeStyle($0.opacity(0.85)) } ?? AnyShapeStyle(.ultraThinMaterial), in: shape)
                .overlay(shape.strokeBorder(GlassRim.gradient, lineWidth: 1))
                .shadow(color: Color.asterShadow.opacity(shadow ? 1 : 0), radius: 18, y: 8)
        }
    }
}

enum GlassRim {
    /// Light catches the upper edge of glass and fades along the lower one.
    static let gradient = LinearGradient(colors: [.asterRimTop, .asterRimBottom], startPoint: .top, endPoint: .bottom)
}

/// In-flow cards and panels: a translucent body, a bright rim and a soft lift. It draws no
/// backdrop of its own (the window's is behind it), so a page of them scrolls freely.
private struct FrostedSurface: ViewModifier {
    var radius: CGFloat
    var tint: Color?
    var lifted: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(tint.map { AnyShapeStyle($0.opacity(0.16)) } ?? AnyShapeStyle(Color.clear), in: shape)
            .background(reduceTransparency ? Color.asterSurface : Color.asterGlass, in: shape)
            .overlay(shape.strokeBorder(GlassRim.gradient, lineWidth: 1))
            .shadow(color: Color.asterShadow.opacity(lifted ? 0.75 : 0.45), radius: lifted ? 20 : 12, y: lifted ? 10 : 5)
    }
}

/// Raises a card slightly while the pointer is over it.
private struct HoverLift: ViewModifier {
    var scale: CGFloat
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View {
        content.scaleEffect(hovering && enabled && !reduceMotion ? scale : 1)
            .brightness(hovering && enabled ? 0.015 : 0)
            .animation(AsterMotion.quick(reduceMotion), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// A list row that fills softly under the pointer.
private struct HoverFill<S: InsettableShape>: ViewModifier {
    var shape: S
    var active: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.background(shape.fill(Color.asterHover.opacity(hovering && !active ? 1 : 0)))
            .animation(AsterMotion.quick(reduceMotion), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Text buttons. The prominent variant is the single accent action of a view.
struct AsterButtonStyle: ButtonStyle {
    var prominent = false
    /// The single main action of a page, such as the welcome's.
    var large = false
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration, prominent: prominent, large: large) }
    private struct Face: View {
        let configuration: ButtonStyle.Configuration
        let prominent: Bool
        let large: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            let shape = Capsule(style: .continuous)
            configuration.label.font(.system(size: large ? 13 : 12, weight: prominent ? .semibold : .medium))
                .padding(.horizontal, large ? 22 : 13).padding(.vertical, large ? 10 : 6)
                .foregroundStyle(prominent ? Color.asterOnAccent : Color.primary)
                .background {
                    if prominent {
                        shape.fill(Color.asterAccent)
                            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.24), .clear], startPoint: .top, endPoint: .center)))
                            .shadow(color: Color.asterAccent.opacity(hovering && enabled ? 0.45 : 0.28), radius: hovering ? 12 : 8, y: 4)
                    } else {
                        shape.fill(Color.asterGlass).overlay(shape.fill(Color.asterHover.opacity(hovering && enabled ? 1 : 0)))
                            .shadow(color: Color.asterShadow.opacity(0.35), radius: 5, y: 2)
                    }
                }
                .overlay(shape.strokeBorder(prominent ? AnyShapeStyle(Color.white.opacity(0.22)) : AnyShapeStyle(GlassRim.gradient), lineWidth: 1))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                .opacity(enabled ? 1 : 0.45)
                .contentShape(shape)
                .animation(AsterMotion.quick(reduceMotion), value: configuration.isPressed)
                .animation(AsterMotion.quick(reduceMotion), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// Rounded text fields set into glass.
struct AsterFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain).padding(.horizontal, 11).padding(.vertical, 7)
            .background(Color.asterWell, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.asterHairline, lineWidth: 1))
    }
}
extension TextFieldStyle where Self == AsterFieldStyle {
    static var aster: AsterFieldStyle { AsterFieldStyle() }
}

extension View {
    /// Floating chrome in real glass. See `GlassChrome`.
    func glassChrome<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false, shadow: Bool = true) -> some View {
        modifier(GlassChrome(shape: shape, tint: tint, interactive: interactive, shadow: shadow))
    }
    func liquidSurface(_ radius: CGFloat = 20, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassChrome(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), tint: tint, interactive: interactive, shadow: true))
    }
    func frostedSurface(_ radius: CGFloat = 22, tint: Color? = nil, lifted: Bool = false) -> some View {
        modifier(FrostedSurface(radius: radius, tint: tint, lifted: lifted))
    }
    /// Lets neighbouring glass shapes morph into each other inside a `LiquidGroup`.
    @ViewBuilder func liquidID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) { glassEffectID(id, in: namespace) } else { self }
    }
    func glassControl(prominent: Bool = false) -> some View { buttonStyle(AsterButtonStyle(prominent: prominent)) }
    func hoverLift(_ scale: CGFloat = 1.012) -> some View { modifier(HoverLift(scale: scale)) }
    func hoverFill<S: InsettableShape>(_ shape: S, active: Bool = false) -> some View { modifier(HoverFill(shape: shape, active: active)) }
    func hoverFill(_ radius: CGFloat = 10, active: Bool = false) -> some View { hoverFill(RoundedRectangle(cornerRadius: radius, style: .continuous), active: active) }
}

/// Glass shapes inside one group share a backdrop pass and blend when they come close.
struct LiquidGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(macOS 26.0, *) { GlassEffectContainer(spacing: spacing) { content() } } else { content() }
    }
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
                .scaleEffect(reduced ? 1 : configuration.isPressed ? 0.965 : hovering && enabled && lift > 0 ? 1.012 : 1)
                .offset(y: reduced || !enabled || configuration.isPressed || !hovering ? 0 : -lift)
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
    /// Toolbar buttons float in real glass; buttons inside cards stay light.
    var chrome = false
    var action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            let icon = Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 30, height: 30).contentTransition(.symbolEffect(.replace))
            if chrome { icon.glassChrome(Circle(), interactive: true, shadow: false) }
            else {
                icon.background(Color.asterGlass, in: Circle()).background(Color.asterHover.opacity(hovering ? 1 : 0), in: Circle())
                    .overlay(Circle().strokeBorder(GlassRim.gradient, lineWidth: 1))
            }
        }.buttonStyle(FluidButtonStyle()).onHover { hovering = $0 }
            .accessibilityLabel(L(title, language: locale.language.languageCode?.identifier)).help(L(title, language: locale.language.languageCode?.identifier))
    }
}

/// A selectable chip, used for modes and moods.
struct ModeChip: View {
    var title: String
    var selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(selected ? Color.asterAccentText : Color.asterMuted)
                .background(selected ? Color.asterAccentSoft : Color.clear, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(selected ? Color.asterAccent.opacity(0.25) : Color.asterHairlineStrong, lineWidth: selected ? 1 : 0.5))
                .hoverFill(Capsule(style: .continuous), active: selected)
                .contentShape(Capsule())
        }.buttonStyle(FluidButtonStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A segmented control whose selection slides as a piece of glass.
struct GlassSegmented<Value: Hashable>: View {
    var options: [(value: Value, title: String)]
    @Binding var selection: Value
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.value == selection
                Button { withAnimation(AsterMotion.spring(reduceMotion)) { selection = option.value } } label: {
                    Text(option.title).font(.system(size: 11.5, weight: selected ? .semibold : .medium)).lineLimit(1)
                        .foregroundStyle(selected ? Color.primary : Color.asterMuted)
                        .padding(.horizontal, 14).frame(maxWidth: .infinity).frame(height: 26)
                        .background {
                            if selected {
                                Capsule(style: .continuous).fill(Color.asterSurface.opacity(0.92))
                                    .overlay(Capsule(style: .continuous).strokeBorder(GlassRim.gradient, lineWidth: 1))
                                    .shadow(color: Color.asterShadow.opacity(0.6), radius: 5, y: 2)
                                    .matchedGeometryEffect(id: "thumb", in: namespace)
                            }
                        }.contentShape(Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            }
        }.padding(3).background(Color.asterWell, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.asterHairline, lineWidth: 1))
    }
}

/// The title of a page with one line under it.
struct PageHeader<Trailing: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L(title)).font(.asterDisplay(30)).tracking(-0.8).lineLimit(2)
                Text(L(subtitle)).font(.system(size: 12.5)).foregroundStyle(Color.asterMuted)
            }
            Spacer(minLength: 12)
            trailing()
        }
    }
}
extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) { self.init(title: title, subtitle: subtitle) { EmptyView() } }
}

/// A key, as printed on the keyboard.
struct KeyCap: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.asterMono(10, weight: .semibold)).foregroundStyle(Color.asterMuted)
            .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 18)
            .background(Color.asterWell, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.asterHairlineStrong, lineWidth: 0.5))
    }
}

/// A ring that fills with progress.
struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 4
    var tint: Color = .asterAccent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().stroke(Color.asterHairlineStrong, lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.001, min(1, progress))).stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)).rotationEffect(.degrees(-90))
        }.animation(AsterMotion.spring(reduceMotion), value: progress).accessibilityHidden(true)
    }
}

/// Content that rises into place the first time it appears; `index` staggers a group.
private struct Arrive: ViewModifier {
    var index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.opacity(shown || reduceMotion ? 1 : 0).offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear { withAnimation(AsterMotion.spring(reduceMotion)?.delay(Double(min(index, 8)) * 0.035)) { shown = true } }
    }
}
extension View {
    func arrive(_ index: Int = 0) -> some View { modifier(Arrive(index: index)) }
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
                Circle().fill(RadialGradient(colors: [Color.asterPollen.opacity(0.26), Color.asterAccent.opacity(0.08), .clear], center: .center, startRadius: 0, endRadius: dimension * 0.62))
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
                }.buttonStyle(FluidButtonStyle(lift: 1)).disabled(!enabled)
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
