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
    func usesBlackHeader(menuBarIsDark: Bool, wallpaperIsDark: Bool?) -> Bool {
        self == .black || (self == .automatic && menuBarIsDark && wallpaperIsDark == true)
    }

}

@MainActor
final class MenuBarAppearance: ObservableObject {
    @Published private(set) var style: MenuBarStyle
    @Published private(set) var usesBlackHeader = false
    private var menuBarIsDark = false
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
            if wallpaperIsDark == nil { return "当前：未取得可靠的菜单栏背景信息，使用连续玻璃。" }
            return usesBlackHeader ? "当前：顶部接近黑色，保留黑色渐变。" : "当前：顶部未满足近黑色条件，使用连续玻璃。"
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
        let match = statusItem?.button?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        menuBarIsDark = match == .darkAqua
        refreshWallpaper()
        resolveStyle()
    }

    private func refreshWallpaper() {
        guard style == .automatic,
              let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let options = NSWorkspace.shared.desktopImageOptions(for: screen),
              let input = WallpaperTone.input(url: url, screenSize: screen.frame.size,
                                              menuHeight: max(NSStatusBar.system.thickness, screen.safeAreaInsets.top),
                                              options: options) else {
            wallpaperTask?.cancel()
            wallpaperTask = nil
            wallpaperInput = nil
            wallpaperIsDark = nil
            return
        }
        guard input != wallpaperInput else { return }
        wallpaperInput = input
        wallpaperIsDark = nil
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
        let black = style.usesBlackHeader(menuBarIsDark: menuBarIsDark, wallpaperIsDark: wallpaperIsDark)
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
