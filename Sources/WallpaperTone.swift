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
    static func input(url: URL, screenSize: CGSize, menuHeight: CGFloat,
                      options: [NSWorkspace.DesktopImageOptionKey: Any]) -> WallpaperToneInput? {
        // A system default image is not reliable evidence of the currently displayed wallpaper.
        guard url.isFileURL,
              url.path != "/System/Library/CoreServices/DefaultDesktop.heic",
              !url.resolvingSymlinksInPath().path.hasPrefix("/System/Library/Wallpapers/.default/"),
              let scaling = (options[.imageScaling] as? NSNumber)?.uintValue,
              scaling == NSImageScaling.scaleAxesIndependently.rawValue ||
                scaling == NSImageScaling.scaleProportionallyUpOrDown.rawValue else { return nil }
        let clips = options[.allowClipping] as? Bool
        guard scaling == NSImageScaling.scaleAxesIndependently.rawValue || clips != nil else { return nil }
        let fill = (options[.fillColor] as? NSColor)?.usingColorSpace(.sRGB)
            ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        return WallpaperToneInput(url: url,
                                  modified: try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                                  screenSize: screenSize, menuHeight: menuHeight, scaling: scaling,
                                  clips: clips ?? false, fill: [fill.redComponent, fill.greenComponent, fill.blueComponent])
    }

    static func isDark(brightness: Double, previous: Bool?) -> Bool {
        // Hysteresis keeps nearby wallpaper tones from toggling the header at every opening.
        brightness.isFinite && brightness < (previous == true ? 0.14 : previous == false ? 0.10 : 0.12)
    }

    static func brightness(_ input: WallpaperToneInput) -> Double? {
        // Unsupported display modes supply no evidence; callers must keep continuous glass.
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
            // Sample only the wallpaper behind the central menu-bar region, never capture screen contents.
            let halfSpan = max(1, min(width / 2, Int(260 / input.screenSize.width * CGFloat(width))))
            let rows = max(1, min(height, Int(ceil(input.menuHeight / input.screenSize.height * CGFloat(height)))))
            let sampleRect = CGRect(x: width / 2 - halfSpan, y: 0, width: halfSpan * 2, height: rows)
            // Never classify synthetic letterbox fill as a black wallpaper top.
            guard imageRect.contains(sampleRect) else { return nil }
            context.interpolationQuality = .medium
            context.draw(image, in: imageRect)
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
