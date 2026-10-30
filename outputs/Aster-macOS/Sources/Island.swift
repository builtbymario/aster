import AppKit
import SwiftUI

/// Where Aster's island sits on a screen and how large each of its states is.
/// On a MacBook it matches the camera notch; elsewhere it hangs from the top center like one.
struct IslandLayout: Equatable {
    /// The largest the open island gets below the notch; it is usually much smaller.
    static let content = CGSize(width: 440, height: 420)
    static let ear: CGFloat = 48
    var screen: CGRect
    var notch: CGSize
    var hasNotch: Bool
    /// The live activity: the notch with an ear on each side.
    var compact: CGSize { CGSize(width: notch.width + Self.ear * 2, height: notch.height) }
    /// The open island: the chat below the notch, never taller than the screen allows.
    var expanded: CGSize { CGSize(width: max(Self.content.width, compact.width), height: min(notch.height + Self.content.height, screen.height - 40)) }
    /// The window spans the open island, hanging from the top center of the screen.
    var panel: CGRect { CGRect(x: screen.midX - expanded.width / 2, y: screen.maxY - expanded.height, width: expanded.width, height: expanded.height) }
    /// Moving the pointer here opens the island: the notch and its ears, up to the top edge.
    var hotZone: CGRect { CGRect(x: screen.midX - compact.width / 2, y: screen.maxY - notch.height - 2, width: compact.width, height: notch.height + 2) }

    static func make(screen: CGRect, safeTop: CGFloat, left: CGRect?, right: CGRect?, menuBar: CGFloat) -> IslandLayout {
        if safeTop > 0, let left, let right {
            return .init(screen: screen, notch: CGSize(width: max(120, screen.width - left.width - right.width), height: safeTop), hasNotch: true)
        }
        return .init(screen: screen, notch: CGSize(width: 180, height: max(24, menuBar)), hasNotch: false)
    }
    /// The built-in display with a notch when there is one, otherwise the main screen.
    static func current() -> IslandLayout? {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first else { return nil }
        return make(screen: screen.frame, safeTop: screen.safeAreaInsets.top, left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea,
                    menuBar: screen.frame.maxY - screen.visibleFrame.maxY)
    }
}

/// The notch silhouette: flat against the top edge, flared top corners and rounded bottom corners.
struct IslandShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4, rect.height / 2)
        let bottom = max(0, min(bottomRadius, rect.height - top, (rect.width - top * 2) / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top), control: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY), control: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom), control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Aster in the notch. At rest it disappears into the notch; while Aster listens, thinks or
/// speaks it widens into a live activity; hovering the notch, ⌥Space or ⌥⌘J open it into the chat.
@MainActor final class NotchIsland: ObservableObject {
    enum Phase { case hidden, resting, open }
    @Published private(set) var phase: Phase = .hidden
    @Published private(set) var layout: IslandLayout
    let panel: MiniChatPanel
    private let store: AsterStore
    private weak var desktop: DesktopCompanions?
    private var monitors: [Any] = []
    private var closeTask: Task<Void, Never>?
    /// The size the island is drawn at right now, reported by its view; hit tests use it.
    var visibleSize = CGSize.zero
    /// Where the island is on screen now, slightly enlarged so the edge is forgiving.
    var visibleFrame: CGRect {
        let size = visibleSize == .zero ? layout.expanded : visibleSize
        return CGRect(x: layout.screen.midX - size.width / 2, y: layout.screen.maxY - size.height, width: size.width, height: size.height).insetBy(dx: -8, dy: -8)
    }
    /// After closing, the notch reopens the island only once the pointer has left it.
    private var armed = true

    init(store: AsterStore, desktop: DesktopCompanions) {
        self.store = store; self.desktop = desktop
        let initial = IslandLayout.current() ?? IslandLayout(screen: CGRect(x: 0, y: 0, width: 1440, height: 900), notch: CGSize(width: 180, height: 24), hasNotch: false)
        layout = initial
        panel = MiniChatPanel(contentRect: initial.panel, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Aster"; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false; panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true; panel.ignoresMouseEvents = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.closeRequested = { [weak desktop] in desktop?.closeChat() }
        panel.contentView = NSHostingView(rootView: IslandView(island: self, desktop: desktop).environmentObject(store))
        let moved: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        let installed: [Any?] = [
            NSEvent.addGlobalMonitorForEvents(matching: moved) { [weak self] _ in Task { @MainActor in self?.pointerMoved() } },
            NSEvent.addLocalMonitorForEvents(matching: moved) { [weak self] event in self?.pointerMoved(); return event },
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in Task { @MainActor in self?.clickedOutside() } }
        ]
        monitors = installed.compactMap { $0 }
    }
    deinit { for monitor in monitors { NSEvent.removeMonitor(monitor) } }

    var isOpen: Bool { phase == .open }
    func show() { guard phase == .hidden else { return }; phase = .resting; panel.orderFrontRegardless() }
    func hide() { closeTask?.cancel(); phase = .hidden; panel.ignoresMouseEvents = true; panel.orderOut(nil) }
    /// Removes the island for good when the floating mascot is chosen instead.
    func teardown() { hide(); for monitor in monitors { NSEvent.removeMonitor(monitor) }; monitors = []; panel.contentView = nil }
    func open() {
        guard phase != .open else { return }
        closeTask?.cancel(); relayout()
        phase = .open; panel.ignoresMouseEvents = false; panel.orderFrontRegardless()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
    func close() {
        guard phase == .open else { return }
        closeTask?.cancel(); phase = .resting; panel.ignoresMouseEvents = true
        armed = !layout.hotZone.contains(NSEvent.mouseLocation)
        if panel.isKeyWindow { panel.resignKey() }
    }
    func relayout() {
        guard let current = IslandLayout.current(), current != layout else { return }
        layout = current; panel.setFrame(current.panel, display: true)
    }
    private func pointerMoved() {
        guard let desktop else { return }
        let pointer = NSEvent.mouseLocation
        switch phase {
        case .resting:
            let inside = layout.hotZone.contains(pointer)
            if inside && armed { desktop.showChat(desktop.currentMode) } else if !inside { armed = true }
        case .open: if visibleFrame.contains(pointer) { closeTask?.cancel() } else { scheduleClose() }
        case .hidden: break
        }
    }
    /// A click anywhere else dismisses the island, unless Aster is listening.
    private func clickedOutside() {
        guard phase == .open, !visibleFrame.contains(NSEvent.mouseLocation), !store.listener.active else { return }
        desktop?.closeChat()
    }
    /// Leaving the island closes it after a moment, unless it was pinned, is listening or holds a draft.
    private func scheduleClose() {
        guard closeTask == nil else { return }
        closeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            guard let self else { return }; self.closeTask = nil
            guard let desktop = self.desktop, self.phase == .open, !self.visibleFrame.contains(NSEvent.mouseLocation),
                  !desktop.pinned, !self.store.listener.active,
                  (desktop.drafts[desktop.currentMode] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            desktop.closeChat()
        }
    }
}

/// Fades content in from a blur as the island opens.
private struct BlurFade: ViewModifier {
    var amount: CGFloat
    func body(content: Content) -> some View { content.blur(radius: amount).opacity(amount > 0 ? 0 : 1) }
}

struct IslandView: View {
    @ObservedObject var island: NotchIsland
    @ObservedObject var desktop: DesktopCompanions
    @EnvironmentObject var store: AsterStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var finished = false
    @State private var finishTask: Task<Void, Never>?
    @State private var contentHeight: CGFloat = 56
    private var style: AvatarStyle { store.state.specialists.first { $0.id == "director" }?.style ?? AvatarStyle() }
    private var mood: AvatarMood { store.mood() }
    private var live: Bool { island.phase == .resting && (mood != .calm || finished) }
    private var size: CGSize {
        switch island.phase {
        case .open: return CGSize(width: island.layout.expanded.width, height: min(island.layout.expanded.height, island.layout.notch.height + contentHeight))
        case .resting: return live ? island.layout.compact : island.layout.notch
        case .hidden: return island.layout.notch
        }
    }
    private var motion: Animation { reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.42, dampingFraction: 0.8) }
    var body: some View {
        let open = island.phase == .open
        let shape = IslandShape(topRadius: open ? 12 : 6, bottomRadius: open ? 28 : island.layout.notch.height * 0.42)
        ZStack(alignment: .top) {
            shape.fill(Color.black)
                .shadow(color: Color.asterRing.opacity(mood == .listening ? 0.55 : 0), radius: 18, y: 4)
                .shadow(color: .black.opacity(open ? 0.3 : 0), radius: 22, y: 10)
            if open {
                VStack(spacing: 0) {
                    Color.clear.frame(height: island.layout.notch.height)
                    IslandChatView(desktop: desktop)
                        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { Color.clear.preference(key: IslandContentHeightKey.self, value: $0.size.height) })
                    Spacer(minLength: 0)
                }.frame(width: size.width, height: size.height, alignment: .top).clipShape(shape)
                    .onPreferenceChange(IslandContentHeightKey.self) { height in if abs(height - contentHeight) > 0.5 { contentHeight = height } }
                    .transition(.asymmetric(insertion: .modifier(active: BlurFade(amount: 12), identity: BlurFade(amount: 0)).animation(motion.delay(0.08)),
                                            removal: .opacity.animation(.easeOut(duration: 0.12))))
            } else if live {
                ears.transition(.modifier(active: BlurFade(amount: 6), identity: BlurFade(amount: 0)))
            }
        }
        .frame(width: size.width, height: size.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(motion, value: island.phase)
        .animation(motion, value: live)
        .animation(motion, value: mood)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: contentHeight)
        .environment(\.colorScheme, .dark)
        .onChange(of: size, initial: true) { _, value in island.visibleSize = value }
        .onChange(of: mood) { old, new in
            guard old == .thinking, new == .calm else { return }
            finished = true; finishTask?.cancel()
            finishTask = Task { try? await Task.sleep(for: .seconds(4)); finished = false }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Aster")
    }
    /// The live activity: Aster on the left ear, what it is doing on the right.
    private var ears: some View {
        HStack(spacing: 0) {
            CompanionAvatar(style: style, mood: mood, dimension: island.layout.notch.height + 4, animateAtRest: true, framesPerSecond: 30)
                .padding(.leading, 12)
            Spacer(minLength: island.layout.notch.width)
            Group {
                switch mood {
                case .listening, .speaking: LiveBars(active: true)
                case .thinking: ThinkingDots()
                default: Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.asterRing)
                }
            }.frame(width: 24).padding(.trailing, 16)
        }.frame(height: island.layout.notch.height).accessibilityHidden(true)
    }
}

/// Five lavender bars that move like a voice.
private struct LiveBars: View {
    var active: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule().fill(Color.asterRing).frame(width: 2.5, height: 4 + 10 * abs(sin(time * 6 + Double(index) * 1.1)))
                }
            }.frame(height: 16)
        }
    }
}

/// Three dots that pulse in turn while Aster thinks.
struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle().fill(Color.asterRing).frame(width: 4, height: 4).opacity(0.3 + 0.7 * (0.5 + 0.5 * sin(time * 4 - Double(index) * 0.9)))
                }
            }
        }
    }
}

