import AppKit
import SwiftUI

/// The expanded panel palette follows SwiftUI's system appearance.
struct PanelAppearance {
    static let compactBackground = NSColor(srgbRed: 0.025, green: 0.027, blue: 0.03, alpha: 1)

    let colorScheme: ColorScheme
    let artworkColor: NSColor

    private var isDark: Bool { colorScheme == .dark }
    private var backgroundWhite: CGFloat { isDark ? 0.09 : 0.97 }
    private var backgroundOpacity: CGFloat { isDark ? 0.90 : 0.88 }

    var surface: Color {
        Color(nsColor: NSColor(srgbRed: backgroundWhite, green: backgroundWhite, blue: backgroundWhite, alpha: backgroundOpacity))
    }

    var deviceButtonFill: Color {
        isDark ? .white.opacity(0.10) : .black.opacity(0.06)
    }

    var headerTint: Color { Color(nsColor: artworkColor).opacity(0.02) }

    var artworkWash: LinearGradient {
        let tint = Color(nsColor: artworkColor)
        return LinearGradient(stops: [
            .init(color: tint.opacity(0.02), location: 0),
            .init(color: tint.opacity(0.045), location: 0.25),
            .init(color: tint.opacity(0.075), location: 0.55),
            .init(color: tint.opacity(0.10), location: 0.80),
            .init(color: tint.opacity(0.085), location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    var progressTint: Color {
        let ink = NSColor(srgbRed: isDark ? 1 : 0, green: isDark ? 1 : 0, blue: isDark ? 1 : 0, alpha: 1)
        guard let artwork = artworkColor.usingColorSpace(.sRGB) else { return Color(nsColor: ink) }
        // Use the lowest-contrast background that can result from desktop bleed and the artwork wash.
        let desktop: CGFloat = isDark ? 1 : 0
        let base = backgroundWhite * backgroundOpacity + desktop * (1 - backgroundOpacity)
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
