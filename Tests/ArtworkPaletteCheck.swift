import AppKit

@main enum ArtworkPaletteCheck {
    static func hsv(_ color: NSColor) -> (h: CGFloat, s: CGFloat, v: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        color.usingColorSpace(.sRGB)!.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return (h, s, v)
    }
    static func difference(_ a: CGFloat, _ b: CGFloat) -> CGFloat { min(abs(a - b), 1 - abs(a - b)) }
    static func image(_ pixel: (Int, Int) -> NSColor) -> NSImage {
        let size = 40
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size { for x in 0..<size {
            let color = pixel(x, y).usingColorSpace(.sRGB)!
            let a = color.alphaComponent
            let offset = (y * size + x) * 4
            for (i, value) in [color.redComponent, color.greenComponent, color.blueComponent, 1].enumerated() {
                bytes[offset + i] = UInt8((value * a * 255).rounded())
            }
        } }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cg = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }
    static func main() {
        precondition(ArtworkPalette.fallback.waveformTop == ArtworkPalette.fallback.secondary)
        precondition(ArtworkPalette.fallback.waveformBottom == ArtworkPalette.fallback.primary,
                     "The grayscale startup placeholder must sort safely before any artwork arrives")
        let blue = NSColor(srgbRed: 0.1, green: 0.3, blue: 0.6, alpha: 1)
        let orange = NSColor(srgbRed: 1, green: 0.6, blue: 0.1, alpha: 1)
        let cover = image { x, _ in x < 28 ? blue : (x < 38 ? orange : .white) }
        let colors = ArtworkPalette.colors(from: cover)
        precondition(difference(hsv(colors.primary).h, hsv(blue).h) < 0.04, "Most common color must lead")
        precondition(hsv(colors.primary).v < 0.65, "Keep the actual cover color without artificial brightening")
        precondition(difference(hsv(colors.secondary).h, hsv(orange).h) < 0.04,
                     "A substantial contrasting hue must survive white highlights")
        precondition(colors.waveformTop == colors.primary && colors.waveformBottom == colors.secondary,
                     "The darker blue must sit above orange without changing the dominant panel tint")
        precondition(ArtworkPalette.colors(from: cover) == colors, "Extraction must be deterministic")

        // A broad gradient must win over a smaller flat patch even when its exact RGB values are all different.
        for dominantHue: CGFloat in [0.08, 0.32, 0.62, 0.83] {
            let gradient = ArtworkPalette.colors(from: image { x, y in
                if x >= 26 { return NSColor(calibratedHue: (dominantHue + 0.4).truncatingRemainder(dividingBy: 1),
                                            saturation: 0.6, brightness: 0.85, alpha: 1) }
                return NSColor(calibratedHue: dominantHue + CGFloat(x - 13) * 0.0015,
                               saturation: 0.35 + CGFloat(y) * 0.014,
                               brightness: 0.45 + CGFloat(x) * 0.018, alpha: 1)
            })
            precondition(difference(hsv(gradient.primary).h, dominantHue) < 0.07,
                         "All shades of the largest hue family must vote together")
        }
        let hueSeam = ArtworkPalette.colors(from: image { x, _ in
            NSColor(calibratedHue: x < 14 ? 0.99 : (x < 28 ? 0.01 : 0.6), saturation: 0.8, brightness: 0.8, alpha: 1)
        })
        precondition(difference(hsv(hueSeam.primary).h, 0) < 0.04, "Red must merge across the hue circle seam")

        let repeated = ArtworkPalette.colors(from: image { x, _ in x < 28 ? .white : (x < 38 ? .gray : .black) })
        precondition(hsv(repeated.primary).v > 0.98)
        precondition(hsv(repeated.secondary).v < 0.02, "Repeated dominant/brightest colors must use the strongest contrasting cover color")

        let dark = ArtworkPalette.colors(from: image { x, _ in x < 30 ? .black : blue })
        precondition(difference(hsv(dark.primary).h, hsv(blue).h) < 0.04, "Black background cannot outvote the cover color")
        precondition(hsv(dark.secondary).v < 0.02)
        let red = ArtworkPalette.colors(from: image { x, y in
            if y < 5 { return NSColor(white: 0.85, alpha: 1) }
            if x >= 18 && x < 22 && y >= 25 && y < 30 { return .red }
            return NSColor(white: 0.08, alpha: 1)
        })
        precondition(difference(hsv(red.primary).h, 0) < 0.04 && hsv(red.primary).s > 0.8,
                     "The red focal color must survive a mostly black/gray cover")
        precondition(hsv(red.secondary).s < 0.02 && hsv(red.secondary).v > 0.8,
                     "Gray-white highlights must remain the secondary color")
        precondition(red.waveformTop == red.primary && red.waveformBottom == red.secondary,
                     "Red must sit above gray-white")
        let blueOnWhite = ArtworkPalette.colors(from: image { x, _ in x < 28 ? blue : .white })
        precondition(difference(hsv(blueOnWhite.primary).h, hsv(blue).h) < 0.04)
        precondition(hsv(blueOnWhite.waveformBottom).s < 0.02 && hsv(blueOnWhite.waveformBottom).v > 0.98)
        precondition(blueOnWhite.waveformTop == blueOnWhite.primary,
                     "A blue cover on white must retain blue across the upper waveform")
        let speckled = ArtworkPalette.colors(from: image { x, y in
            if x == 0 && y == 0 { return orange }
            return x < 28 ? blue : .white
        })
        precondition(hsv(speckled.secondary).s < 0.02,
                     "An isolated contrasting pixel cannot replace a real background color")
        let bordered = ArtworkPalette.colors(from: image { x, y in y < 10 ? .clear : (x < 28 ? blue : orange) })
        precondition(difference(hsv(bordered.primary).h, hsv(blue).h) < 0.04)
        precondition(difference(hsv(bordered.secondary).h, hsv(orange).h) < 0.04)
        let single = ArtworkPalette.colors(from: image { _, _ in blue })
        precondition(single.primary == single.secondary, "A solid cover cannot invent a second color")
        precondition(ArtworkPalette.colors(from: image { _, _ in .clear }) == ArtworkPalette.fallback)
        print("PASS hue-area primary, substantial contrasting secondary, neutral fallback, dark-on-top order, transparency, and deterministic extraction")
    }
}
