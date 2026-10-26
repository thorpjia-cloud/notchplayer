import AppKit

enum ArtworkPalette {
    struct Colors: Equatable {
        let primary: NSColor
        let secondary: NSColor
    }

    static let fallback = Colors(primary: NSColor(white: 0.72, alpha: 1),
                                 secondary: NSColor(white: 0.50, alpha: 1))

    private struct Swatch {
        var count: CGFloat = 0
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var color: NSColor {
            NSColor(srgbRed: red / count, green: green / count, blue: blue / count, alpha: 1)
        }
    }

    private static func brightness(_ color: NSColor) -> CGFloat {
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        // Perceived brightness keeps saturated blue from tying with white just because both peak at 255.
        return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent)
            + 0.0722 * linear(color.blueComponent)
    }

    private static func difference(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let r = a.redComponent - b.redComponent
        let g = a.greenComponent - b.greenComponent
        let blue = a.blueComponent - b.blueComponent
        return sqrt((r * r + g * g + blue * blue) / 3)
    }

    private static func isCoverColor(_ color: NSColor) -> Bool {
        var hue: CGFloat = 0, saturation: CGFloat = 0, value: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &value, alpha: &alpha)
        // Neutral backgrounds and near-black compression noise must not outvote the cover's actual color.
        return saturation >= 0.25 && value >= 0.25
    }

    static func colors(from image: NSImage) -> Colors {
        var proposed = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return fallback }
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard rendered else { return fallback }
        // Count nearby RGB colors together so JPEG noise doesn't split one cover color into many votes.
        var bins = [Swatch](repeating: Swatch(), count: 512)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = CGFloat(pixels[i + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = min(1, CGFloat(pixels[i]) / 255 / alpha)
            let g = min(1, CGFloat(pixels[i + 1]) / 255 / alpha)
            let b = min(1, CGFloat(pixels[i + 2]) / 255 / alpha)
            let key = min(7, Int(r * 8)) * 64 + min(7, Int(g * 8)) * 8 + min(7, Int(b * 8))
            bins[key].count += alpha
            bins[key].red += r * alpha; bins[key].green += g * alpha; bins[key].blue += b * alpha
        }
        let colors = bins.enumerated().filter { $0.element.count > 0 }.sorted {
            $0.element.count == $1.element.count ? $0.offset < $1.offset : $0.element.count > $1.element.count
        }.map { $0.element.color }
        guard let primary = colors.first(where: isCoverColor) ?? colors.first else { return fallback }
        var lightest = primary
        var contrast = primary
        for color in colors {
            if brightness(color) > brightness(lightest) { lightest = color }
            if difference(primary, color) > difference(primary, contrast) { contrast = color }
        }
        // If the most common and brightest colors repeat, use the farthest actual cover color.
        return Colors(primary: primary, secondary: difference(primary, lightest) < 0.12 ? contrast : lightest)
    }
}
