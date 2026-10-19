import AppKit
import ImageIO

struct WallpaperToneInput: Equatable, Sendable {
    let url: URL
    let modified: Date?
    let screenSize: CGSize
    let menuHeight: CGFloat
    let scaling: UInt
    let clips: Bool
    let fill: [CGFloat]
}

enum WallpaperTone {
    static func isDark(brightness: Double, previous: Bool?) -> Bool {
        // Hysteresis keeps nearby wallpaper tones from toggling the header at every opening.
        brightness < (previous == true ? 0.30 : previous == false ? 0.22 : 0.26)
    }

    static func brightness(_ input: WallpaperToneInput) -> Double? {
        // Non-scaling wallpaper modes lack reliable point sizing; retain the native appearance fallback.
        guard input.scaling == NSImageScaling.scaleAxesIndependently.rawValue ||
                input.scaling == NSImageScaling.scaleProportionallyUpOrDown.rawValue else { return nil }
        guard input.url.isFileURL, input.screenSize.width > 0, input.screenSize.height > 0,
              let source = CGImageSourceCreateWithURL(input.url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let width = 128
        let height = max(1, Int((CGFloat(width) * input.screenSize.height / input.screenSize.width).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { bytes -> Double? in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
            let canvas = CGRect(x: 0, y: 0, width: width, height: height)
            context.setFillColor(CGColor(red: input.fill[0], green: input.fill[1], blue: input.fill[2], alpha: 1))
            context.fill(canvas)
            var imageRect = canvas
            if input.scaling != NSImageScaling.scaleAxesIndependently.rawValue {
                let sx = CGFloat(width) / CGFloat(image.width), sy = CGFloat(height) / CGFloat(image.height)
                let scale = input.clips ? max(sx, sy) : min(sx, sy)
                let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                imageRect = CGRect(x: (CGFloat(width) - size.width) / 2, y: (CGFloat(height) - size.height) / 2,
                                   width: size.width, height: size.height)
            }
            context.interpolationQuality = .medium
            context.draw(image, in: imageRect)
            // Sample only the wallpaper behind the central menu-bar region, never capture screen contents.
            let halfSpan = max(1, min(width / 2, Int(260 / input.screenSize.width * CGFloat(width))))
            let rows = max(1, min(height, Int(ceil(input.menuHeight / input.screenSize.height * CGFloat(height)))))
            let data = bytes.bindMemory(to: UInt8.self)
            var sum = 0.0
            var count = 0
            for y in 0..<rows {
                for x in (width / 2 - halfSpan)..<(width / 2 + halfSpan) {
                    let offset = (y * width + x) * 4
                    sum += (0.2126 * Double(data[offset]) + 0.7152 * Double(data[offset + 1]) + 0.0722 * Double(data[offset + 2])) / 255
                    count += 1
                }
            }
            return count > 0 ? sum / Double(count) : nil
        }
    }
}
