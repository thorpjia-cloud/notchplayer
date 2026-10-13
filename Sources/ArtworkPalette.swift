import AppKit

// Use a small hue histogram so white borders and dark shadows don't wash out album colors.
enum ArtworkPalette {
    static let fallback = NSColor(white: 0.72, alpha: 1)
    static func glassTint(from accent: NSColor) -> NSColor {
        guard let rgb = accent.usingColorSpace(.sRGB) else { return NSColor(white: 0.6, alpha: 1) }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        guard saturation > 0.12 else { return NSColor(white: 0.6, alpha: 1) }
        // Keep the cover hue recognizable without making the glass look like a saturated fill.
        return NSColor(calibratedHue: hue, saturation: min(0.58, max(0.42, saturation * 0.80)),
                       brightness: min(0.74, max(0.62, brightness * 0.86)), alpha: 1)
    }
    static func accent(from image: NSImage) -> NSColor {
        var proposed = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return fallback }
        let size = 32
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        var weights = [CGFloat](repeating: 0, count: 24)
        var sums = [(r: CGFloat, g: CGFloat, b: CGFloat)](repeating: (0, 0, 0), count: 24)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard rendered else { return fallback }
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = CGFloat(pixels[i + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = min(1, CGFloat(pixels[i]) / 255 / alpha)
            let g = min(1, CGFloat(pixels[i + 1]) / 255 / alpha)
            let b = min(1, CGFloat(pixels[i + 2]) / 255 / alpha)
            let color = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
            guard s > 0.16, v > 0.12 else { continue }
            let bin = min(23, Int(h * 24))
            let weight = s * s * sqrt(v) * alpha
            weights[bin] += weight
            sums[bin].r += r * weight; sums[bin].g += g * weight; sums[bin].b += b * weight
        }
        guard let bin = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[bin] > 1 else { return fallback }
        let color = NSColor(srgbRed: sums[bin].r / weights[bin], green: sums[bin].g / weights[bin], blue: sums[bin].b / weights[bin], alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(calibratedHue: hue, saturation: min(0.82, max(0.4, saturation)), brightness: max(0.78, brightness), alpha: 1)
    }
}
