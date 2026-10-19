import AppKit
import ImageIO

@main enum WallpaperToneCheck {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func fixture(top: UInt8, bottom: UInt8, name: String) -> URL {
            let width = 80, height = 60
            var bytes = [UInt8](repeating: 255, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    let value = y < 8 ? top : bottom
                    let index = (y * width + x) * 4
                    bytes[index] = value; bytes[index + 1] = value; bytes[index + 2] = value
                }
            }
            let provider = CGDataProvider(data: Data(bytes) as CFData)!
            let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            let url = folder.appendingPathComponent(name + ".png")
            let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, image, nil)
            precondition(CGImageDestinationFinalize(destination))
            return url
        }
        func sample(_ url: URL) -> Double? {
            WallpaperTone.brightness(.init(url: url, modified: nil, screenSize: CGSize(width: 800, height: 600),
                                          menuHeight: 30, scaling: NSImageScaling.scaleAxesIndependently.rawValue,
                                          clips: false, fill: [0, 0, 0]))
        }
        precondition(sample(fixture(top: 0, bottom: 255, name: "dark-top"))! < 0.05)
        precondition(sample(fixture(top: 255, bottom: 0, name: "light-top"))! > 0.95)
        precondition(WallpaperTone.isDark(brightness: 0.1, previous: nil))
        precondition(!WallpaperTone.isDark(brightness: 0.5, previous: nil))
        precondition(WallpaperTone.isDark(brightness: 0.25, previous: true))
        precondition(!WallpaperTone.isDark(brightness: 0.25, previous: false))
        precondition(sample(folder.appendingPathComponent("missing.png")) == nil)
        print("Wallpaper top-row selection, dark/light classification, hysteresis and missing-file fallback passed")
        if CommandLine.arguments.count > 1, let value = sample(URL(fileURLWithPath: CommandLine.arguments[1])) {
            print("Supplied wallpaper brightness: \(value), dark: \(WallpaperTone.isDark(brightness: value, previous: nil))")
        }
    }
}
