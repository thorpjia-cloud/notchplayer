import AppKit

enum ArtworkPalette {
    struct Colors: Equatable {
        let primary: NSColor
        let secondary: NSColor

        // Dark-to-light ordering is independent of which hue supplies the panel tint.
        var waveformTop: NSColor { brightness(primary) <= brightness(secondary) ? primary : secondary }
        var waveformBottom: NSColor { brightness(primary) <= brightness(secondary) ? secondary : primary }
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
        mutating func add(_ other: Swatch) {
            count += other.count; red += other.red; green += other.green; blue += other.blue
        }
    }

    private static func brightness(_ color: NSColor) -> CGFloat {
        // App startup uses a grayscale fallback; RGB component access requires conversion first.
        guard let color = color.usingColorSpace(.sRGB) else { return 0 }
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

    private static func hueDistance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let distance = abs(a.hueComponent - b.hueComponent)
        return min(distance, 1 - distance)
    }

    private static func shade(_ swatches: [Swatch], percentile: CGFloat) -> NSColor? {
        let sorted = swatches.sorted { brightness($0.color) < brightness($1.color) }
        let threshold = sorted.reduce(CGFloat.zero) { $0 + $1.count } * percentile
        var count: CGFloat = 0
        for swatch in sorted {
            count += swatch.count
            if count >= threshold { return swatch.color }
        }
        return nil
    }

    private static func hueFamilies(in swatches: [Swatch]) -> [Swatch] {
        let binCount = 72
        var hues = [Swatch](repeating: Swatch(), count: binCount)
        for swatch in swatches {
            var hue: CGFloat = 0, saturation: CGFloat = 0, value: CGFloat = 0, alpha: CGFloat = 0
            swatch.color.getHue(&hue, saturation: &saturation, brightness: &value, alpha: &alpha)
            // Background neutrals and near-black compression noise do not vote for the dominant hue.
            guard saturation >= 0.25, value >= 0.25 else { continue }
            hues[min(binCount - 1, Int(hue * CGFloat(binCount)))].add(swatch)
        }
        var groups: [Swatch] = []
        for center in 0..<binCount {
            var group = Swatch()
            // A circular 45-degree hue neighborhood combines one color's lighting/gradient variations.
            // Area, not any individual RGB shade or saturation, determines the winning color family.
            for offset in -4...4 { group.add(hues[(center + offset + binCount) % binCount]) }
            if group.count > 0 { groups.append(group) }
        }
        return groups.enumerated().sorted {
            $0.element.count == $1.element.count ? $0.offset < $1.offset : $0.element.count > $1.element.count
        }.map(\.element)
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
        let ranked = bins.enumerated().filter { $0.element.count > 0 }.sorted {
            $0.element.count == $1.element.count ? $0.offset < $1.offset : $0.element.count > $1.element.count
        }.map(\.element)
        let colors = ranked.map(\.color)
        let families = hueFamilies(in: ranked)
        guard var primary = families.first?.color ?? colors.first else { return fallback }
        if let family = families.first {
            // Hue area chooses the family; a populated, colorful swatch avoids muddy shadow averages.
            let representatives = ranked.filter {
                $0.count >= max(2, family.count * 0.005) && $0.color.saturationComponent >= 0.25
                    && hueDistance(primary, $0.color) <= 1.0 / 32
            }
            func score(_ swatch: Swatch) -> CGFloat {
                let color = swatch.color
                return color.saturationComponent * pow(color.brightnessComponent, 2)
            }
            if let representative = representatives.max(by: { score($0) < score($1) }) { primary = representative.color }
        }
        let area = ranked.reduce(CGFloat.zero) { $0 + $1.count }
        // A second substantial hue is more representative than a tiny white reflection or lettering.
        // Area times color separation favors a real contrasting region over isolated colored speckles.
        let contrastingFamily = families.filter {
            $0.count >= area * 0.02 && hueDistance(primary, $0.color) >= 1.0 / 6
        }.max {
            $0.count * difference(primary, $0.color) < $1.count * difference(primary, $1.color)
        }
        if let contrastingFamily {
            return Colors(primary: primary, secondary: contrastingFamily.color)
        }
        if !families.isEmpty {
            let brightNeutrals = ranked.filter { $0.color.saturationComponent < 0.18 && brightness($0.color) > 0.08 }
            let neutralArea = brightNeutrals.reduce(CGFloat.zero) { $0 + $1.count }
            // A white background matters; tiny white lettering should not turn a warm cover's bars white.
            if neutralArea >= area * 0.08 {
                return Colors(primary: primary, secondary: shade(brightNeutrals, percentile: 0.85)!)
            }
            let shades = ranked.filter {
                $0.color.saturationComponent >= 0.25 && $0.color.brightnessComponent >= 0.25 && hueDistance(primary, $0.color) < 1.0 / 8
            }
            if let shadow = shade(shades, percentile: 0.20) {
                // Use a real shadow tone from the same hue family when no second region is present.
                return Colors(primary: primary, secondary: shadow)
            }
        }
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
