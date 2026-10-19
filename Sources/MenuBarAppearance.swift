import AppKit
import Combine

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case automatic, black, glass
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "跟随菜单栏"
        case .black: return "黑色渐变"
        case .glass: return "统一玻璃"
        }
    }
}

@MainActor
final class MenuBarAppearance: ObservableObject {
    @Published private(set) var style: MenuBarStyle
    @Published private(set) var usesBlackHeader = true
    private var menuBarIsDark = true
    private var wallpaperIsDark: Bool?
    private var wallpaperInput: WallpaperToneInput?
    private var wallpaperTask: Task<Void, Never>?
    private var spaceObservation: NSObjectProtocol?
    private var statusItem: NSStatusItem?
    private var appearanceObservation: NSKeyValueObservation?
    private let preferenceKey = "menuBarStyle"

    init() {
        style = MenuBarStyle(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .automatic
        resolveStyle()
    }

    var detail: String {
        if style == .automatic {
            return usesBlackHeader ? "当前：深色菜单栏，保留黑色渐变。" : "当前：浅色菜单栏，顶部与面板使用连续玻璃。"
        }
        return usesBlackHeader ? "展开后菜单栏区域纯黑，向下过渡到玻璃。" : "展开后顶部与下方共用透明玻璃和专辑染色。"
    }

    func start() {
        guard statusItem == nil else { return }
        // A zero-width item inherits the menu bar's wallpaper-dependent appearance without adding an icon.
        let item = NSStatusBar.system.statusItem(withLength: 0)
        statusItem = item
        appearanceObservation = item.button?.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        spaceObservation = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        guard let appearance = statusItem?.button?.effectiveAppearance,
              let match = appearance.bestMatch(from: [.aqua, .darkAqua]) else { return }
        menuBarIsDark = match == .darkAqua
        refreshWallpaper()
        resolveStyle()
    }

    private func refreshWallpaper() {
        guard style == .automatic else { return }
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            wallpaperTask?.cancel()
            wallpaperInput = nil
            wallpaperIsDark = nil
            return
        }
        let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        let fill = (options[.fillColor] as? NSColor)?.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let input = WallpaperToneInput(url: url,
                                       modified: try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                                       screenSize: screen.frame.size,
                                       menuHeight: max(NSStatusBar.system.thickness, screen.safeAreaInsets.top),
                                       scaling: (options[.imageScaling] as? NSNumber)?.uintValue ?? NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                                       clips: (options[.allowClipping] as? Bool) ?? false,
                                       fill: [fill.redComponent, fill.greenComponent, fill.blueComponent])
        guard input != wallpaperInput else { return }
        wallpaperInput = input
        wallpaperTask?.cancel()
        wallpaperTask = Task { [weak self] in
            let brightness = await Task.detached(priority: .utility) { WallpaperTone.brightness(input) }.value
            guard !Task.isCancelled, let self else { return }
            // White menu-bar icons can still sit on a light wallpaper; appearance alone does not imply black.
            self.wallpaperIsDark = brightness.map { WallpaperTone.isDark(brightness: $0, previous: self.wallpaperIsDark) }
            self.resolveStyle()
        }
    }

    func setStyle(_ value: MenuBarStyle) {
        guard style != value else { return }
        style = value
        UserDefaults.standard.set(value.rawValue, forKey: preferenceKey)
        refresh()
        resolveStyle()
    }

    private func resolveStyle() {
        let darkBackground = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? true : wallpaperIsDark ?? true
        let black = style == .black || (style == .automatic && menuBarIsDark && darkBackground)
        if usesBlackHeader != black { usesBlackHeader = black }
    }

    func stop() {
        wallpaperTask?.cancel()
        if let spaceObservation { NSWorkspace.shared.notificationCenter.removeObserver(spaceObservation) }
        spaceObservation = nil
        appearanceObservation?.invalidate()
        appearanceObservation = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }
}
