import AppKit
import SwiftUI

enum ExpandedPanelStyle: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

final class ExpandedPanelSettings: ObservableObject {
    private static let key = "ExpandedPanelStyle"
    private let defaults: UserDefaults
    @Published var style: ExpandedPanelStyle {
        didSet { defaults.set(style.rawValue, forKey: Self.key) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        style = defaults.string(forKey: Self.key).flatMap(ExpandedPanelStyle.init(rawValue:)) ?? .system
    }
}

/// The expanded panel palette follows the window's effective appearance.
struct PanelAppearance {
    static let compactBackground = NSColor(srgbRed: 0.025, green: 0.027, blue: 0.03, alpha: 1)

    let colorScheme: ColorScheme
    let artworkColor: NSColor

    private var isDark: Bool { colorScheme == .dark }
    private var backgroundWhite: CGFloat { isDark ? 0.09 : 0.97 }
    private var progressReferenceOpacity: CGFloat { isDark ? 0.90 : 0.88 }

    var surface: Color {
        let opacity: CGFloat = isDark ? progressReferenceOpacity : 0.50
        return Color(nsColor: NSColor(srgbRed: backgroundWhite, green: backgroundWhite, blue: backgroundWhite, alpha: opacity))
    }

    var progressTint: Color {
        let ink = NSColor(srgbRed: isDark ? 1 : 0, green: isDark ? 1 : 0, blue: isDark ? 1 : 0, alpha: 1)
        guard let artwork = artworkColor.usingColorSpace(.sRGB) else { return Color(nsColor: ink) }
        // Keep the progress tint on its existing contrast reference while testing the lighter surface.
        let desktop: CGFloat = isDark ? 1 : 0
        let base = backgroundWhite * progressReferenceOpacity + desktop * (1 - progressReferenceOpacity)
        let reference = Self.linearize(base * 0.90 + desktop * 0.10)
        for step in 0...10 {
            let fraction = CGFloat(step) / 10
            guard let candidate = artwork.blended(withFraction: fraction, of: ink)?.usingColorSpace(.sRGB) else { break }
            let luminance = 0.2126 * Self.linearize(candidate.redComponent)
                + 0.7152 * Self.linearize(candidate.greenComponent)
                + 0.0722 * Self.linearize(candidate.blueComponent)
            if (max(luminance, reference) + 0.05) / (min(luminance, reference) + 0.05) >= 3 {
                return Color(nsColor: candidate)
            }
        }
        return Color(nsColor: ink)
    }

    private static func linearize(_ channel: CGFloat) -> CGFloat {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
}
