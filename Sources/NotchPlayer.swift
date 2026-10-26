import AppKit
import SwiftUI
import Combine

final class NookModel: ObservableObject {
    @Published var musicVisible = false
    @Published var acceptsInteraction = false
    @Published var hardwareNotchWidth: CGFloat = 164
    @Published var hardwareNotchLeadingOffset: CGFloat = -82
    @Published var expanded = false {
        didSet { if oldValue != expanded { expansionChanged?() } }
    }
    var expansionChanged: (() -> Void)?
    @Published var nativeGlassIsActive = false
    @Published var usesBlackHeader = true
    @Published var pinned = false
    @Published var hovering = false
    @Published var scrubbing = false
    private(set) var outputPickerPresented = false
    weak var outputPickerButton: NSButton?
    @Published var dragX: CGFloat = 0
    @Published var dragY: CGFloat = 0
    @Published var closedWidth: CGFloat = CompactNotchLayout.width(notchWidth: 164)
    @Published var topHeight: CGFloat = 32
    var requestClose: (() -> Void)?
    var showSettings: (() -> Void)?
    var checkForUpdates: (() -> Void)?
    private var closeWork: DispatchWorkItem?
    var spring: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.56, dampingFraction: 0.9, blendDuration: 0)
    }
    var closingAnimation: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeOut(duration: 0.15)
            : .spring(response: 0.42, dampingFraction: 0.94, blendDuration: 0)
    }
    let resetSpring = Animation.spring(response: 0.5, dampingFraction: 1, blendDuration: 0)
    // Hover is a preview state; only a click opens the music controls.
    var width: CGFloat { expanded ? 360 : closedWidth + (hovering ? 12 : 0) }
    var height: CGFloat { expanded ? topHeight + 100 : topHeight }
    var hoverFeedback: () -> Void = {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
    private var lastFeedback = Date.distantPast
    func open() {
        guard musicVisible && acceptsInteraction else { return }
        closeWork?.cancel(); withAnimation(spring) { expanded = true }
    }
    func prepareForHide() {
        closeWork?.cancel()
        pinned = false; scrubbing = false; hovering = false
        expanded = false; dragX = 0; dragY = 0
    }
    func close(force: Bool = false) {
        guard force || (!pinned && !scrubbing && !outputPickerPresented) else { return }
        closeWork?.cancel()
        withAnimation(closingAnimation) { expanded = false; dragX = 0; dragY = 0 }
    }
    func hover(_ value: Bool) {
        guard acceptsInteraction else { return }
        guard value != hovering else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { hovering = value }
        if value {
            closeWork?.cancel()
            if !expanded && Date().timeIntervalSince(lastFeedback) > 0.2 {
                lastFeedback = Date()
                hoverFeedback()
            }
        } else { scheduleClose() }
    }
    func scheduleClose() {
        closeWork?.cancel()
        guard acceptsInteraction && !pinned && !scrubbing && !outputPickerPresented else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hovering, !self.pinned, !self.scrubbing, !self.outputPickerPresented else { return }
            self.close()
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }
    func setOutputPickerPresented(_ presented: Bool) {
        outputPickerPresented = presented
        if presented { closeWork?.cancel() } else { scheduleClose() }
    }
}
struct StableBackdrop: NSViewRepresentable {
    var expanded: Bool
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        // Keep the blur independent of which app owns keyboard focus.
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.alphaValue = expanded ? 0.38 : 0
    }
}

// Derive light timing from the same reversible progress as the expanding geometry.
private func glassReveal(_ progress: CGFloat, from start: CGFloat, to end: CGFloat) -> Double {
    let t = min(1, max(0, (progress - start) / (end - start)))
    return Double(t * t * (3 - 2 * t))
}

struct SiriGlassSurface: View, Animatable {
    var nativeGlassIsActive: Bool
    var usesBlackHeader: Bool
    var topHeight: CGFloat
    var progress: CGFloat
    var artworkTint: Color
    var outline: NotchOutline
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    private var reveal: Double { glassReveal(progress, from: 0.08, to: 0.88) }
    var body: some View {
        ZStack {
            if #available(macOS 26.0, *) {
                // Full native optics need the active window path; masking them suppresses the actual lensing.
                Color.clear
                    .glassEffect(.clear.interactive(false), in: outline)
                    .glassEffectTransition(.identity)
                    .opacity(nativeGlassIsActive ? reveal : 0)
                    .environment(\.appearsActive, true)
                    .materialActiveAppearance(.active)
            } else {
                StableBackdrop(expanded: true).clipShape(outline).opacity(reveal)
            }
            artworkWash
            // GeometryReader prevents the transition layer's fixed height from enlarging the collapsed background.
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Color.clear.frame(height: min(topHeight, geometry.size.height))
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.84), location: 0.20),
                        .init(color: .black.opacity(0.42), location: 0.45),
                        .init(color: .black.opacity(0.12), location: 0.70),
                        .init(color: .black.opacity(0.02), location: 0.88),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: min(8, max(0, geometry.size.height - topHeight)))
                    Spacer(minLength: 0)
                }
            }
            .clipShape(outline)
            .opacity(usesBlackHeader ? reveal : 0)
            outline
                .fill(Color(red: 0.025, green: 0.027, blue: 0.03))
                .opacity(1 - reveal)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var artworkWash: some View {
        // Separate neutral absorption from the cover hue so the color reads as part of the glass.
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Extend the first wash color upward without moving the established lower gradient.
                Color.black.opacity(0.38)
                    .overlay(artworkTint.opacity(0.02))
                    .opacity(usesBlackHeader ? 0 : 1)
                    .frame(height: min(topHeight, geometry.size.height))
                LinearGradient(stops: [
                    .init(color: artworkTint.opacity(0.02), location: 0),
                    .init(color: artworkTint.opacity(0.045), location: 0.25),
                    .init(color: artworkTint.opacity(0.075), location: 0.55),
                    .init(color: artworkTint.opacity(0.10), location: 0.80),
                    .init(color: artworkTint.opacity(0.085), location: 1)
                ], startPoint: .top, endPoint: .bottom)
                .background {
                    // Neutral absorption controls white-background glare while leaving the native lens unmasked.
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.38), location: 0),
                        .init(color: .black.opacity(0.32), location: 0.24),
                        .init(color: .black.opacity(0.27), location: 0.55),
                        .init(color: .black.opacity(0.235), location: 0.80),
                        .init(color: .black.opacity(0.22), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: artworkTint)
        .clipShape(outline)
        .opacity(reveal)
    }
}

private struct GlassExteriorMask: Shape {
    var margin: CGFloat
    var outline: NotchOutline
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let innerSize = CGSize(width: max(0, rect.width - margin * 2),
                               height: max(0, rect.height - margin * 2))
        path.addPath(outline.path(in: CGRect(origin: .zero, size: innerSize))
            .offsetBy(dx: margin, dy: margin))
        return path
    }
}

struct GlassLiftShadow: View {
    var progress: CGFloat
    var outline: NotchOutline
    var body: some View {
        GeometryReader { geometry in
            let margin: CGFloat = 36
            // Cut out the lens interior so lift and contact shadows cannot tint the clear center.
            outline.fill(.black)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 7)
                .shadow(color: .black.opacity(0.16), radius: 2.5, y: 1.5)
                .padding(margin)
                .mask { GlassExteriorMask(margin: margin, outline: outline).fill(.white, style: FillStyle(eoFill: true)) }
                .offset(x: -margin, y: -margin)
        }
        .opacity(glassReveal(progress, from: 0.22, to: 0.92))
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct GlassReflectionStroke: View {
    var topHeight: CGFloat
    var progress: CGFloat
    var outline: NotchOutline
    private var rim: NotchOutline {
        var shape = outline
        shape.drawsTopEdge = false
        return shape
    }
    var body: some View {
        // A directional hairline stays legible between the sparse native specular peaks.
        rim
            .stroke(LinearGradient(stops: [
                .init(color: .white.opacity(0.08), location: 0),
                .init(color: .white.opacity(0.55), location: 0.24),
                .init(color: .white.opacity(0.08), location: 0.48),
                .init(color: .white.opacity(0.20), location: 0.78),
                .init(color: .white.opacity(0.12), location: 1)
            ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.0)
            .shadow(color: .black.opacity(0.16), radius: 0.35, y: 0.5)
            .mask {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        Color.clear.frame(height: min(topHeight, geometry.size.height))
                        LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
                            .frame(height: min(8, max(0, geometry.size.height - topHeight)))
                        Color.white
                    }
                }
            }
            .opacity(glassReveal(progress, from: 0.22, to: 0.90))
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct NotchMorph: AnimatableModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var nativeGlassIsActive: Bool
    var usesBlackHeader: Bool
    var artworkTint: Color
    var progress: CGFloat
    var presence: CGFloat
    var notchWidth: CGFloat
    var closedWidth: CGFloat
    var closedHeight: CGFloat
    var topHeight: CGFloat
    var dragX: CGFloat
    var dragY: CGFloat
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(progress, presence), .init(closedWidth, closedHeight)) }
        set {
            progress = newValue.first.first; presence = newValue.first.second
            closedWidth = newValue.second.first; closedHeight = newValue.second.second
        }
    }
    func body(content: Content) -> some View {
        let size = GlassMotion.size(progress: progress,
                                    closed: CGSize(width: closedWidth, height: closedHeight),
                                    open: CGSize(width: 360, height: topHeight + 100))
        let tension = reduceMotion ? 0 : GlassMotion.presenceTension(progress: presence) * (1 - min(1, max(0, progress)))
        let outline = NotchOutline(compactHeight: topHeight, compactTension: tension)
        content
            .frame(width: (reduceMotion ? size.width : GlassMotion.presenceWidth(progress: presence, notchWidth: notchWidth, visibleWidth: size.width)) + abs(dragX) * 0.1,
                   height: size.height + dragY * 0.12, alignment: .top)
            .clipShape(outline)
            .background {
                SiriGlassSurface(nativeGlassIsActive: nativeGlassIsActive, usesBlackHeader: usesBlackHeader, topHeight: topHeight,
                                 progress: progress, artworkTint: artworkTint, outline: outline)
            }
            .background { GlassLiftShadow(progress: progress, outline: outline) }
            .overlay { GlassReflectionStroke(topHeight: usesBlackHeader ? topHeight : 0, progress: progress, outline: outline) }
            .overlay {
                // Only dark menu bars need an opaque cap; the native lens remains continuous underneath.
                Color.black.frame(height: topHeight)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipShape(outline)
                    .opacity(usesBlackHeader ? glassReveal(progress, from: 0, to: 1) : 0)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .opacity(glassReveal(presence, from: 0, to: 0.28))
    }
}

private struct CompactWingReveal: AnimatableModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var progress: CGFloat
    var inwardOffset: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        let reveal = glassReveal(progress, from: 0.24, to: 0.94)
        content.opacity(reveal)
            .offset(x: reduceMotion ? 0 : inwardOffset * (1 - reveal))
    }
}

struct MusicView: View {
    @ObservedObject var model: NookModel
    @ObservedObject var media: MediaService
    private var accent: Color { Color(nsColor: media.artworkColors.primary) }
    private var glassTint: Color { accent }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                if model.expanded {
                    controls.transition(.opacity.combined(with: .offset(y: -8)))
                }
            }
            .modifier(NotchMorph(nativeGlassIsActive: model.nativeGlassIsActive, usesBlackHeader: model.usesBlackHeader, artworkTint: glassTint,
                                 progress: model.expanded ? 1 : 0,
                                 presence: model.musicVisible ? 1 : 0,
                                 notchWidth: model.hardwareNotchWidth,
                                 closedWidth: model.closedWidth + (model.hovering ? 12 : 0),
                                 closedHeight: model.topHeight,
                                 topHeight: model.topHeight, dragX: model.dragX, dragY: model.dragY))
            .offset(x: model.dragX * 0.12)
            .contentShape(NotchOutline(compactHeight: model.topHeight))
            .contextMenu {
                Button("设置…") { model.showSettings?() }
                Button("检查更新…") { model.checkForUpdates?() }
                Divider()
                Button("使用说明") {
                    if let url = Bundle.main.url(forResource: "使用说明", withExtension: "txt") { NSWorkspace.shared.open(url) }
                }
                Button("重新连接播放器", action: media.reconnect)
                Divider()
                Button("退出 notchplayer") { NSApp.terminate(nil) }
            }
            .overlay {
                if !model.expanded {
                    Button { model.open() } label: {
                        Color.clear.contentShape(NotchOutline(compactHeight: model.topHeight))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("展开音乐播放器")
                }
            }
            .allowsHitTesting(model.acceptsInteraction)
            .accessibilityHidden(!model.acceptsInteraction)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            if model.expanded {
                // Anchor to hardware in the fixed host, outside the panel's resize and drag transforms.
                AudioOutputPicker(volume: media.volume, presentationChanged: model.setOutputPickerPresented,
                                  buttonReady: { model.outputPickerButton = $0 })
                    .frame(width: 24, height: 24)
                    .offset(x: model.hardwareNotchLeadingOffset - 12 - 4,
                            y: max(0, (model.topHeight - 24) / 2))
                    .transition(.opacity)
                    .allowsHitTesting(model.acceptsInteraction)
                    .accessibilityHidden(!model.acceptsInteraction)
            }
        }
        .ignoresSafeArea(.all)
        .preferredColorScheme(.dark)
        .environment(\.appearsActive, true)
    }
    private var header: some View {
        HStack {
            if !model.expanded {
                cover(size: min(CompactNotchLayout.artworkSize, model.topHeight - 8)).accessibilityLabel("展开音乐播放器")
                    .modifier(CompactWingReveal(progress: model.musicVisible ? 1 : 0, inwardOffset: 12))
                Spacer(minLength: 0)
                bars.frame(width: 20, height: 16).accessibilityLabel(media.playing ? "正在播放" : "播放已暂停")
                    .modifier(CompactWingReveal(progress: model.musicVisible ? 1 : 0, inwardOffset: -12))
            }
        }
        // Keep the hardware notch area clear while the music controls sit below it.
        .padding(.horizontal, CompactNotchLayout.outerInset).frame(height: model.topHeight)
    }
    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Button(action: media.previous) {
                        Image(systemName: "backward.fill").font(.system(size: 13, weight: .regular)).frame(width: 28, height: 36)
                    }.accessibilityLabel("上一首").help("上一首")
                    Button(action: media.toggle) {
                        Image(systemName: media.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 19, weight: .regular))
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 34, height: 36)
                    }.accessibilityLabel(media.playing ? "暂停" : "播放")
                    Button(action: media.next) {
                        Image(systemName: "forward.fill").font(.system(size: 13, weight: .regular)).frame(width: 28, height: 36)
                    }.accessibilityLabel("下一首").help("下一首")
                }
                .buttonStyle(TransportButtonStyle(cornerRadius: NotchCorners.radius * model.topHeight / 32))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white.opacity(0.94))
                .shadow(color: .black.opacity(0.55), radius: 0.8, y: 0.5)
                .disabled(!media.available)
                cover(size: 48)
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                // Separate metadata lines preserve room for both long artists and album names.
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeTitle(text: media.title)
                    MarqueeTitle(text: media.artist, fontSize: 11, weight: .regular, lineHeight: 14)
                        .foregroundStyle(.white.opacity(0.94))
                    if !media.album.isEmpty {
                        MarqueeTitle(text: media.album, fontSize: 11, weight: .regular, lineHeight: 14)
                            .foregroundStyle(.white.opacity(0.88))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 60)
            HStack(spacing: 8) {
                PlaybackProgressControl(progress: media.progress, duration: media.duration,
                                        available: media.available, accent: accent, seek: media.seek) { editing in
                    model.scrubbing = editing
                    if !editing { model.scheduleClose() }
                }
                VolumeControl(volume: media.volume) { editing in
                    model.scrubbing = editing
                    if !editing { model.scheduleClose() }
                }.frame(width: 90)

            }
            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
            .frame(height: 16)
            .padding(.trailing, 14)
        }.padding(.leading, 28).padding(.trailing, 18).padding(.top, 6).padding(.bottom, 10)
    }
    private func cover(size: CGFloat) -> some View {
        Group {
            if let artwork = media.artwork { Image(nsImage: artwork).resizable().scaledToFill() }
            else {
                ZStack {
                    LinearGradient(colors: [.gray.opacity(0.2), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: size * 0.32)).foregroundStyle(.white.opacity(0.55))
                }
            }
        }.frame(width: size, height: size)
            // Preserve the large cover's proportions instead of turning the 22 pt thumbnail into a pill.
            .clipShape(RoundedRectangle(cornerRadius: NotchCorners.radius * min(1, size / 48) * model.topHeight / 32,
                                        style: .circular))
    }
    private var bars: some View {
        SpectrumBars(spectrum: media.spectrum,
                     upper: Color(nsColor: media.artworkColors.waveformTop),
                     lower: Color(nsColor: media.artworkColors.waveformBottom))
    }
}

struct PlaybackProgressControl: View {
    @ObservedObject var progress: PlaybackProgress
    var duration: Double
    var available: Bool
    var accent: Color
    var seek: (Double) -> Void
    var editingChanged: (Bool) -> Void
    private var seekValue = State<Double>(initialValue: 0)
    private var scrubbing = State<Bool>(initialValue: false)

    var body: some View {
        Slider(value: seekValue.projectedValue, in: 0...max(1, duration), onEditingChanged: { editing in
            scrubbing.wrappedValue = editing
            editingChanged(editing)
            if !editing { seek(seekValue.wrappedValue) }
        }).tint(accent).controlSize(.mini)
            .environment(\.appearsActive, true)
            .animation(.easeInOut(duration: 0.35), value: accent)
            .disabled(!available || duration <= 0).accessibilityLabel("播放进度")
            .onAppear { seekValue.wrappedValue = progress.position }
            .onChange(of: progress.position) { _, value in
                if !scrubbing.wrappedValue { seekValue.wrappedValue = value }
            }
    }
}

struct VolumeControl: View {
    @ObservedObject var volume: OutputVolume
    var editingChanged: (Bool) -> Void
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: volume.value == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                .frame(width: 14).accessibilityHidden(true)
            Slider(value: Binding(get: { volume.value }, set: { volume.set($0) }), in: 0...1,
                   onEditingChanged: editingChanged)
                .controlSize(.mini).tint(.white.opacity(0.75))
                .disabled(!volume.available)
                .accessibilityLabel("系统输出音量")
                .accessibilityValue("\(Int((volume.value * 100).rounded()))%")
        }
        .help(volume.available ? "系统输出音量" : "当前输出设备不支持系统音量调整")
    }
}

struct SpectrumBars: View {
    @ObservedObject var spectrum: AudioSpectrum
    var upper: Color
    var lower: Color
    var body: some View {
        SpectrumBarDisplay(levels: spectrum.levels, upper: upper, lower: lower)
            .help(spectrum.status)
    }
}

final class NookHostingView: NSHostingView<MusicView> {
    // The first click should act even while another app owns keyboard focus.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NookPanel: NSPanel {
    // Glass effects must not re-enable a WindowServer shadow for the collapsed notch.
    override var hasShadow: Bool {
        get { false }
        set { super.hasShadow = false }
    }
    var topEdgeClick: ((NSPoint) -> Bool)?
    private var consumedTopEdgePress = false
    override func sendEvent(_ event: NSEvent) {
        // NSMenu can consume the matching mouse-up in its own tracking loop.
        if event.type == .leftMouseDown { consumedTopEdgePress = false }
        // Top-edge controls need the same window-level routing as the collapsed notch.
        if event.type == .leftMouseDown, topEdgeClick?(event.locationInWindow) == true {
            consumedTopEdgePress = true
            return
        }
        if event.type == .leftMouseUp && consumedTopEdgePress {
            consumedTopEdgePress = false
            return
        }
        super.sendEvent(event)
    }
    // Allow native active optics only while the click-opened panel is being used.
    var acceptsKeyboardFocus = false
    override var canBecomeKey: Bool { acceptsKeyboardFocus }
    override var canBecomeMain: Bool { false }
    // AppKit's default constraint moves borderless windows below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    var escape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { escape?() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = NookModel()
    let media = MediaService()
    let appUpdater = AppUpdater()
    let menuBarAppearance = MenuBarAppearance()
    lazy var settings = SettingsWindowController(updater: appUpdater, menuBarAppearance: menuBarAppearance)
    private var appearanceSubscription: AnyCancellable?
    private var launchedAtLogin = false
    var panel: NookPanel!
    var mouseTimer: Timer?
    var monitor: Any?
    var screenObserver: NSObjectProtocol?
    var globalClickMonitor: Any?
    var totalX: CGFloat = 0
    var totalY: CGFloat = 0
    var gestureEnd: DispatchWorkItem?
    var focusRelease: DispatchWorkItem?
    var dismissedUntilExit = false
    var presenceSubscription: AnyCancellable?
    var presenceGeneration = 0
    func applicationWillFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAtLogin = event?.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem) != nil
            || event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBarAppearance.start()
        model.usesBlackHeader = menuBarAppearance.usesBlackHeader
        appearanceSubscription = menuBarAppearance.$usesBlackHeader.removeDuplicates().sink { [weak self] black in
            withAnimation(.easeInOut(duration: 0.25)) { self?.model.usesBlackHeader = black }
        }
        installApplicationMenu()
        model.showSettings = { [weak self] in self?.showSettings() }
        model.checkForUpdates = { [weak self] in self?.checkForUpdates() }
        appUpdater.showSettings = { [weak self] in self?.showSettings() }
        appUpdater.start()
        panel = NookPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.isMovable = false; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true; panel.becomesKeyOnlyIfNeeded = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.title = "notchplayer · 音乐"
        panel.delegate = self
        let hostingView = NookHostingView(rootView: MusicView(model: model, media: media))
        // The panel has a fixed host frame; waveform changes must not remeasure window size constraints.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.topEdgeClick = { [weak self] point in
            guard let self, self.model.acceptsInteraction else { return false }
            let screenPoint = self.panel.convertPoint(toScreen: point)
            if self.openOutputPicker(at: screenPoint) { return true }
            guard !self.model.expanded else { return false }
            guard self.interactionRect.contains(screenPoint) else { return false }
            self.expand()
            return true
        }
        model.expansionChanged = { [weak self] in
            guard let self else { return }
            self.media.progress.setVisible(self.model.expanded)
            self.panel.hasShadow = false
            self.panel.invalidateShadow()
            self.focusRelease?.cancel()
            if self.model.expanded {
                self.menuBarAppearance.refresh()
                self.panel.acceptsKeyboardFocus = true
                self.panel.makeKey()
                self.model.nativeGlassIsActive = self.panel.isKeyWindow
            } else {
                // Retain active native optics until the closing morph has hidden the glass.
                let release = DispatchWorkItem { [weak self] in
                    guard let self, !self.model.expanded else { return }
                    self.panel.acceptsKeyboardFocus = false
                    self.panel.resignKey()
                    self.model.nativeGlassIsActive = false
                }
                self.focusRelease = release
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: release)
            }
        }
        panel.escape = { [weak self] in self?.collapse() }
        model.requestClose = { [weak self] in self?.collapse() }
        placeWindow()
        panel.ignoresMouseEvents = true
        presenceSubscription = media.$sessionActive.removeDuplicates().sink { [weak self] in self?.setMusicPresence($0) }
        media.start()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { [weak self] event in
            guard let self, self.model.acceptsInteraction else { return event }
            if self.model.outputPickerPresented { return event }
            if event.type == .keyDown && event.keyCode == 53 && event.window === self.panel { self.collapse(); return nil }
            if event.type == .scrollWheel && event.window === self.panel && !self.model.scrubbing { self.scroll(event); return nil }
            return event
        }
        // The menu-bar/notch strip can route real clicks to another process.
        // Handle only our collapsed region and expanded output button; no global keyboard monitoring.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self, self.model.acceptsInteraction else { return }
            let point = NSEvent.mouseLocation
            if self.openOutputPicker(at: point) { return }
            guard !self.model.expanded else { return }
            guard self.interactionRect.contains(point) else { return }
            self.expand()
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.placeWindow(); self?.menuBarAppearance.refresh() }
        }
        // The media stream stays connected while the window is absent.
        if !launchedAtLogin && !CommandLine.arguments.contains("--background") {
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }
    @objc func showSettings() { collapse(); settings.show() }
    @objc func checkForUpdates() { showSettings(); appUpdater.checkForUpdates() }

    private func installApplicationMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "notchplayer")
        for (title, action, key) in [("设置…", #selector(showSettings), ","),
                                      ("检查更新…", #selector(checkForUpdates), "")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            appMenu.addItem(item)
        }
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 notchplayer", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 notchplayer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }
    private func setMusicPresence(_ visible: Bool) {
        presenceGeneration += 1
        let generation = presenceGeneration
        model.acceptsInteraction = false
        panel.ignoresMouseEvents = true
        mouseTimer?.invalidate(); mouseTimer = nil
        gestureEnd?.cancel()
        panel.contentView?.menu?.cancelTracking()
        model.outputPickerButton?.menu?.cancelTracking()
        if visible {
            dismissedUntilExit = true
            model.prepareForHide()
            panel.orderFrontRegardless()
            panel.displayIfNeeded()
            // Commit the hidden geometry before starting a reveal, without recreating the window.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.presenceGeneration == generation else { return }
                let animation: Animation = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    ? .easeOut(duration: 0.18) : .smooth(duration: 0.82)
                withAnimation(animation, completionCriteria: .removed) {
                    self.model.musicVisible = true
                } completion: { [weak self] in
                    guard let self, self.presenceGeneration == generation else { return }
                    self.model.acceptsInteraction = true
                    let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                        MainActor.assumeIsolated { self?.trackMouse() }
                    }
                    self.mouseTimer = timer
                    RunLoop.main.add(timer, forMode: .common)
                }
            }
        } else {
            let animation: Animation = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? .easeOut(duration: 0.15) : .smooth(duration: 0.62)
            withAnimation(animation, completionCriteria: .removed) {
                model.prepareForHide()
                model.musicVisible = false
            } completion: { [weak self] in
                guard let self, self.presenceGeneration == generation else { return }
                self.panel.orderOut(nil)
                self.focusRelease?.cancel()
                self.panel.acceptsKeyboardFocus = false
                self.panel.resignKey()
                self.model.nativeGlassIsActive = false
            }
        }
    }
    func windowDidBecomeKey(_ notification: Notification) {
        if model.expanded { model.nativeGlassIsActive = true }
    }
    func windowDidResignKey(_ notification: Notification) {
        guard !model.outputPickerPresented else { return }
        // Hide the inactive material immediately, then let the rim and geometry close normally.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { model.nativeGlassIsActive = false }
        if model.expanded { collapse() }
    }
    func placeWindow() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let menuBarInset = screen.frame.maxY - screen.visibleFrame.maxY
        let reservedTop = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : NSStatusBar.system.thickness
        // Hover may widen the notch, but its resting and hovered heights must fit the menu bar.
        model.topHeight = menuBarInset > 0 ? min(reservedTop, menuBarInset) : reservedTop
        var notchWidth: CGFloat = 164
        var notchLeadingOffset: CGFloat = -notchWidth / 2
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = max(130, right.minX - left.maxX)
            notchLeadingOffset = left.maxX - screen.frame.midX
        }
        model.hardwareNotchWidth = notchWidth
        model.hardwareNotchLeadingOffset = notchLeadingOffset
        model.closedWidth = CompactNotchLayout.width(notchWidth: notchWidth)
        panel.setFrame(NSRect(x: screen.frame.midX - 330, y: screen.frame.maxY - 320, width: 660, height: 320), display: true)
        // Record geometry only so the physical top-edge invariant can be checked.
        let line = "screen=\(screen.frame) visible=\(screen.visibleFrame) panel=\(panel.frame) safeTop=\(screen.safeAreaInsets.top) menuBarInset=\(menuBarInset) compactHeight=\(model.topHeight)\n"
        try? line.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("nooklab-geometry.txt"), atomically: true, encoding: .utf8)
    }
    var interactionRect: NSRect {
        let inset: CGFloat = model.expanded ? 14 : 6 * model.topHeight / 32
        return NSRect(x: panel.frame.midX - model.width / 2 + inset,
               y: panel.frame.maxY - model.height,
               width: model.width - 2 * inset, height: model.height)
    }
    private func openOutputPicker(at screenPoint: NSPoint) -> Bool {
        guard model.acceptsInteraction, model.expanded, !model.outputPickerPresented,
              let button = model.outputPickerButton, button.window === panel,
              button.convert(button.bounds, to: nil).contains(panel.convertPoint(fromScreen: screenPoint)) else { return false }
        model.setOutputPickerPresented(true)
        // Leave mouse-event dispatch before entering NSMenu's tracking loop.
        DispatchQueue.main.async { [weak self, weak button] in
            guard let self, let button, self.model.expanded else {
                self?.model.setOutputPickerPresented(false)
                return
            }
            self.panel.makeKey()
            button.performClick(nil)
        }
        return true
    }
    func trackMouse() {
        guard model.acceptsInteraction, !model.outputPickerPresented else { return }
        let point = NSEvent.mouseLocation
        let inside = interactionRect.contains(point)
        // Reassigning this property also commits AppKit window tags even when the value is unchanged.
        if panel.ignoresMouseEvents != !inside { panel.ignoresMouseEvents = !inside }
        if !inside { dismissedUntilExit = false }
        model.hover(inside && !dismissedUntilExit)

    }
    func scroll(_ event: NSEvent) {
        guard model.expanded else { return }
        if !event.momentumPhase.isEmpty { return }
        if event.phase == .began { totalX = 0; totalY = 0 }
        totalX += event.scrollingDeltaX; totalY += event.scrollingDeltaY
        model.dragX = max(-60, min(60, totalX)); model.dragY = max(-35, min(45, totalY))
        gestureEnd?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if abs(self.totalX) > abs(self.totalY), abs(self.totalX) > 45 {
                if self.totalX > 0 { self.media.previous() } else { self.media.next() }
            } else if self.totalY > 24 { self.collapse() }
            withAnimation(self.model.resetSpring) { self.model.dragX = 0; self.model.dragY = 0 }
            self.totalX = 0; self.totalY = 0
        }
        gestureEnd = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (event.phase == .ended ? 0 : 0.16), execute: work)
    }
    @objc func expand() { dismissedUntilExit = false; model.open() }
    @objc func collapse() { dismissedUntilExit = true; model.hover(false); model.close(force: true); panel.invalidateShadow() }
    @objc func togglePin() { model.pinned.toggle(); if model.pinned { model.open() } else { model.scheduleClose() } }
    @objc func reconnect() { media.reconnect() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        appearanceSubscription?.cancel()
        menuBarAppearance.stop()
        presenceSubscription?.cancel()
        media.stop(); mouseTimer?.invalidate(); focusRelease?.cancel()
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }
}

@main enum NotchPlayer {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
