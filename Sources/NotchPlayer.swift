import AppKit
import SwiftUI
import Combine

final class NookModel: ObservableObject {
    @Published var musicVisible = false
    @Published var acceptsInteraction = false
    @Published var layout = NotchLayout()
    @Published var expanded = false {
        didSet { if oldValue != expanded { expansionChanged?() } }
    }
    var expansionChanged: (() -> Void)?
    @Published var nativeGlassIsActive = false
    @Published var usesBlackHeader = false
    @Published var pinned = false
    @Published var hovering = false
    @Published var scrubbing = false
    private(set) var outputPickerPresented = false
    weak var outputPickerButton: NSButton?
    @Published var dragX: CGFloat = 0
    @Published var dragY: CGFloat = 0
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
    var hoverFeedback: () -> Void = {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
    private var lastFeedback = Date.distantPast
    // Hover previews the compact panel; opening requires a separate action.
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
        view.appearance = nil
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.state = .active
        view.appearance = nil
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
    var panelAppearance: PanelAppearance
    var outline: NotchOutline
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    private var reveal: Double { glassReveal(progress, from: 0.08, to: 0.88) }
    private var nativeLensOutline: NotchOutline {
        var lens = outline
        lens.opticalTopExtension = 32
        return lens
    }
    var body: some View {
        ZStack {
            if #available(macOS 26.0, *) {
                // Full native optics need the active window path; masking them suppresses the actual lensing.
                Color.clear
                    .glassEffect(.clear.interactive(false), in: nativeLensOutline)
                    .glassEffectTransition(.identity)
                    .opacity(nativeGlassIsActive ? reveal : 0)
                    .environment(\.appearsActive, true)
                    .materialActiveAppearance(.active)
            } else {
                StableBackdrop(expanded: true).clipShape(outline).opacity(reveal)
            }
            outline.fill(panelAppearance.surface).opacity(reveal)
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
                .fill(Color(nsColor: PanelAppearance.compactBackground))
                .opacity(1 - reveal)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var artworkWash: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                panelAppearance.headerTint
                    .opacity(usesBlackHeader ? 0 : 1)
                    .frame(height: min(topHeight, geometry.size.height))
                panelAppearance.artworkWash
            }
        }
        .animation(.easeInOut(duration: 0.35), value: panelAppearance.artworkColor)
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
    var panelAppearance: PanelAppearance
    var progress: CGFloat
    var presence: CGFloat
    var layout: NotchLayout
    var closedSize: CGSize
    var dragX: CGFloat
    var dragY: CGFloat
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(progress, presence), .init(closedSize.width, closedSize.height)) }
        set {
            progress = newValue.first.first; presence = newValue.first.second
            closedSize = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }
    func body(content: Content) -> some View {
        let topHeight = layout.topHeight
        let size = GlassMotion.size(progress: progress, closed: closedSize, open: layout.expandedSize)
        let tension = reduceMotion ? 0 : GlassMotion.presenceTension(progress: presence) * (1 - min(1, max(0, progress)))
        let outline = NotchOutline(compactHeight: topHeight, compactTension: tension)
        content
            .frame(width: (reduceMotion ? size.width : GlassMotion.presenceWidth(progress: presence, notchWidth: layout.hardwareWidth, visibleWidth: size.width)) + abs(dragX) * 0.1,
                   height: size.height + dragY * 0.12, alignment: .top)
            .modifier(NotchCornerContainer(topHeight: topHeight, height: size.height))
            .clipShape(outline)
            .background {
                SiriGlassSurface(nativeGlassIsActive: nativeGlassIsActive, usesBlackHeader: usesBlackHeader, topHeight: topHeight,
                                 progress: progress, panelAppearance: panelAppearance, outline: outline)
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
    @Environment(\.colorScheme) private var colorScheme
    private var panelAppearance: PanelAppearance {
        PanelAppearance(colorScheme: colorScheme, artworkColor: media.artworkColors.primary)
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                if model.expanded {
                    controls.transition(.opacity.combined(with: .offset(y: -8)))
                }
            }
            .modifier(NotchMorph(nativeGlassIsActive: model.nativeGlassIsActive, usesBlackHeader: model.usesBlackHeader, panelAppearance: panelAppearance,
                                 progress: model.expanded ? 1 : 0,
                                 presence: model.musicVisible ? 1 : 0,
                                 layout: model.layout, closedSize: model.layout.compactSize(hovering: model.hovering),
                                 dragX: model.dragX, dragY: model.dragY))
            .offset(x: model.dragX * 0.12)
            .contentShape(NotchOutline(compactHeight: model.layout.topHeight))
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
                        Color.clear.contentShape(NotchOutline(compactHeight: model.layout.topHeight))
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
        .ignoresSafeArea(.all)
        .environment(\.appearsActive, true)
    }
    private var header: some View {
        HStack {
            if !model.expanded {
                cover(size: model.layout.compactArtworkSize).accessibilityLabel("展开音乐播放器")
                    .modifier(CompactWingReveal(progress: model.musicVisible ? 1 : 0, inwardOffset: 12))
                Spacer(minLength: 0)
                bars.frame(width: 20, height: 16).accessibilityLabel(media.playing ? "正在播放" : "播放已暂停")
                    .modifier(CompactWingReveal(progress: model.musicVisible ? 1 : 0, inwardOffset: -12))
            }
        }
        // Keep the hardware notch area clear while the music controls sit below it.
        .padding(.horizontal, NotchLayout.compactOuterInset).frame(height: model.layout.topHeight)
    }
    private var controls: some View {
        HStack(alignment: .center, spacing: 16) {
            cover(size: NotchLayout.expandedArtworkSize)
                .shadow(color: .black.opacity(0.25), radius: 7, y: 3)
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    MarqueeTitle(text: media.title, fontSize: 15, lineHeight: 18)
                    MarqueeTitle(text: media.artist, fontSize: 11, weight: .regular, lineHeight: 14)
                        .foregroundStyle(.secondary)
                    if !media.album.isEmpty {
                        MarqueeTitle(text: media.album, fontSize: 10, weight: .regular, lineHeight: 12)
                            .foregroundStyle(.secondary)
                    }
                }.frame(height: 44, alignment: .top)
                Spacer(minLength: 0)
                PlaybackProgressControl(progress: media.progress, duration: media.duration,
                                        available: media.available, accent: panelAppearance.progressTint, seek: media.seek,
                                        showsTimes: true) { editing in
                    model.scrubbing = editing
                    if !editing { model.scheduleClose() }
                }.frame(height: 24)
                HStack(spacing: 14) {
                    Button(action: media.previous) {
                        Image(systemName: "backward.fill").font(.system(size: 17)).frame(width: 40, height: 30)
                    }.accessibilityLabel("上一首").help("上一首")
                    Button(action: media.toggle) {
                        Image(systemName: media.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 24))
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 44, height: 30)
                    }.accessibilityLabel(media.playing ? "暂停" : "播放")
                    Button(action: media.next) {
                        Image(systemName: "forward.fill").font(.system(size: 17)).frame(width: 40, height: 30)
                    }.accessibilityLabel("下一首").help("下一首")
                }
                .buttonStyle(TransportButtonStyle(cornerRadius: NotchCorners.radius * model.layout.topHeight / 32))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
                .disabled(!media.available)
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                VolumeControl(volume: media.volume) { editing in
                    model.scrubbing = editing
                    if !editing { model.scheduleClose() }
                }.frame(height: 16)
                Spacer(minLength: 0)
                AudioOutputPicker(volume: media.volume, presentationChanged: model.setOutputPickerPresented,
                                  buttonReady: { model.outputPickerButton = $0 }, showsName: true)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background { DeviceCornerBackground(fill: panelAppearance.deviceButtonFill) }
            }
            .frame(maxWidth: .infinity).frame(height: NotchLayout.expandedArtworkSize)
        }
        .padding(.horizontal, NotchCorners.topRadius * model.layout.topHeight / 32 + NotchCorners.contentInset)
        .padding(.vertical, NotchCorners.contentInset)
        .frame(height: NotchLayout.expandedContentHeight)
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
            .modifier(ArtworkCornerClip(expanded: model.expanded, size: size, topHeight: model.layout.topHeight))
    }
    private var bars: some View {
        SpectrumBars(spectrum: media.spectrum,
                     gradients: media.artworkColors.waveformGradients(barCount: SpectrumAnalyzer.ranges.count,
                                                                      background: PanelAppearance.compactBackground))
    }
}

struct PlaybackProgressControl: View {
    @ObservedObject var progress: PlaybackProgress
    var duration: Double
    var available: Bool
    var accent: Color
    var seek: (Double) -> Void
    var showsTimes = false
    var editingChanged: (Bool) -> Void
    private var seekValue = State<Double>(initialValue: 0)
    private var scrubbing = State<Bool>(initialValue: false)

    var body: some View {
        VStack(spacing: 2) {
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
        if showsTimes {
            HStack {
                Text(MediaService.time(scrubbing.wrappedValue ? seekValue.wrappedValue : progress.position))
                Spacer()
                Text("−" + MediaService.time(max(0, duration - (scrubbing.wrappedValue ? seekValue.wrappedValue : progress.position))))
            }
            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("播放时间")
            .accessibilityValue("\(MediaService.time(progress.position))，剩余 \(MediaService.time(max(0, duration-progress.position)))")
        }
        }
    }
}

struct VolumeControl: View {
    @ObservedObject var volume: OutputVolume
    var editingChanged: (Bool) -> Void
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: volume.value == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(width: 14).accessibilityHidden(true)
            Slider(value: Binding(get: { volume.value }, set: { volume.set($0) }), in: 0...1,
                   onEditingChanged: editingChanged)
                .controlSize(.mini)
                .disabled(!volume.available)
                .accessibilityLabel("系统输出音量")
                .accessibilityValue("\(Int((volume.value * 100).rounded()))%")
        }
        .help(volume.available ? "系统输出音量" : "当前输出设备不支持系统音量调整")
    }
}

struct SpectrumBars: View {
    @ObservedObject var spectrum: AudioSpectrum
    var gradients: [ArtworkPalette.WaveformGradient]
    var body: some View {
        SpectrumBarDisplay(levels: spectrum.levels, gradients: gradients)
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
        panel.appearance = nil
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
        let notchGap = screen.auxiliaryTopLeftArea.flatMap { left in
            screen.auxiliaryTopRightArea.map { $0.minX - left.maxX }
        }
        let layout = NotchLayout(reservedTop: reservedTop, menuBarInset: menuBarInset, notchGap: notchGap)
        if model.layout != layout { model.layout = layout }
        panel.setFrame(NotchLayout.panelFrame(on: screen.frame), display: true)
        // Record geometry only so the physical top-edge invariant can be checked.
        let line = "screen=\(screen.frame) visible=\(screen.visibleFrame) panel=\(panel.frame) safeTop=\(screen.safeAreaInsets.top) menuBarInset=\(menuBarInset) compactHeight=\(model.layout.topHeight)\n"
        try? line.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("nooklab-geometry.txt"), atomically: true, encoding: .utf8)
    }
    var interactionRect: NSRect {
        model.layout.interactionRect(in: panel.frame, expanded: model.expanded, hovering: model.hovering)
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
