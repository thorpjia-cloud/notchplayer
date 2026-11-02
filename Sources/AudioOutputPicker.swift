import AppKit
import SwiftUI
import CoreAudio

struct AudioOutputDevice {
    let id: AudioDeviceID
    let name: String
    let transport: UInt32

    var symbol: String {
        switch transport {
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "display"
        case kAudioDeviceTransportTypeUSB: return "cable.connector"
        default: return "speaker.wave.2"
        }
    }
}

enum SystemAudioOutput {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static var currentDevice: AudioDeviceID? { uint32(system, kAudioHardwarePropertyDefaultOutputDevice) }

    static func name(of device: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr, let name else { return "音频设备" }
        return name.takeRetainedValue() as String
    }

    static func devices() -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = ids.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr else { return [] }
        return ids.prefix(Int(size) / MemoryLayout<AudioDeviceID>.size).compactMap { id in
            // Exclude microphones and private capture/aggregate devices from the user's output menu.
            guard uint32(id, kAudioDevicePropertyDeviceIsAlive) == 1,
                  uint32(id, kAudioDevicePropertyIsHidden) != 1,
                  uint32(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: kAudioDevicePropertyScopeOutput) == 1 else { return nil }
            return AudioOutputDevice(id: id, name: name(of: id), transport: uint32(id, kAudioDevicePropertyTransportType) ?? 0)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func select(_ device: AudioDeviceID) -> OSStatus {
        // Revalidate at selection time because headphones can disconnect while the menu is open.
        guard devices().contains(where: { $0.id == device }) else { return kAudioHardwareBadDeviceError }
        if currentDevice == device { return noErr }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = device
        return AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device)
    }
}

// Center the symbol and the truncated name as one unit; imageLeading alone anchors
// the image to the left edge while reserving the remaining width for the title.
private final class CenteredOutputButtonCell: NSButtonCell {
    private func contentRects(_ bounds: NSRect) -> (image: NSRect, title: NSRect) {
        let icon: CGFloat = 13
        let gap: CGFloat = title.isEmpty ? 0 : 7
        let font = self.font ?? .systemFont(ofSize: 10, weight: .medium)
        let textSize = (title as NSString).size(withAttributes: [.font: font])
        let textWidth = min(ceil(textSize.width), max(0, bounds.width - 24 - icon - gap))
        let width = icon + gap + textWidth
        let x = bounds.midX - width / 2
        return (NSRect(x: x, y: bounds.midY - icon / 2, width: icon, height: icon),
                NSRect(x: x + icon + gap, y: bounds.midY - ceil(textSize.height) / 2,
                       width: textWidth, height: ceil(textSize.height)))
    }

    override func imageRect(forBounds rect: NSRect) -> NSRect { contentRects(rect).image }
    override func titleRect(forBounds rect: NSRect) -> NSRect { contentRects(rect).title }

    override func drawInterior(withFrame frame: NSRect, in view: NSView) {
        let rects = contentRects(frame)
        let tint = (view as? NSButton)?.contentTintColor ?? .labelColor
        let opacity: CGFloat = isHighlighted ? 0.55 : 1
        if let image {
            let symbol = image.withSymbolConfiguration(.init(paletteColors: [tint])) ?? image
            let scale = min(rects.image.width / symbol.size.width, rects.image.height / symbol.size.height)
            let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            let imageRect = NSRect(x: rects.image.midX - size.width / 2,
                                   y: rects.image.midY - size.height / 2, width: size.width, height: size.height)
            symbol.draw(in: imageRect, from: .zero, operation: .sourceOver,
                        fraction: opacity, respectFlipped: true, hints: nil)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in: rects.title, withAttributes: [
            .font: font ?? .systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: tint.withAlphaComponent(tint.alphaComponent * opacity),
            .paragraphStyle: paragraph
        ])
    }
}

struct AudioOutputPicker: NSViewRepresentable {
    @ObservedObject var volume: OutputVolume
    var presentationChanged: (Bool) -> Void
    var buttonReady: (NSButton) -> Void
    var showsName = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "airplayaudio", accessibilityDescription: "播放设备")!,
                              target: context.coordinator, action: #selector(Coordinator.showDevices(_:)))
        button.cell = CenteredOutputButtonCell(imageCell: NSImage(systemSymbolName: "airplayaudio", accessibilityDescription: nil))
        button.target = context.coordinator
        button.action = #selector(Coordinator.showDevices(_:))
        button.isBordered = false
        button.bezelStyle = .inline
        button.imagePosition = .imageOnly
        button.contentTintColor = .white.withAlphaComponent(0.88)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        button.setAccessibilityIdentifier("audio-output-picker")
        buttonReady(button)
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.volume = volume
        context.coordinator.presentationChanged = presentationChanged
        button.title = showsName ? volume.outputName : ""
        button.imagePosition = showsName ? .imageLeading : .imageOnly
        button.font = .systemFont(ofSize: 10, weight: .medium)
        button.lineBreakMode = .byTruncatingTail
        button.toolTip = "播放设备：\(volume.outputName)"
        button.setAccessibilityLabel("播放设备：\(volume.outputName)")
    }

    final class Coordinator: NSObject {
        weak var volume: OutputVolume?
        var presentationChanged: (Bool) -> Void = { _ in }
        private var selectionError: OSStatus?

        @objc func showDevices(_ button: NSButton) {
            // Keep the notch and its native glass active while the menu tracks outside the panel.
            presentationChanged(true)
            defer { volume?.refresh(); presentationChanged(false) }
            selectionError = nil
            let menu = NSMenu()
            button.menu = menu
            defer { button.menu = nil }
            menu.autoenablesItems = false
            let heading = NSMenuItem(title: "声音输出", action: nil, keyEquivalent: "")
            heading.isEnabled = false
            menu.addItem(heading)
            let current = SystemAudioOutput.currentDevice
            let devices = SystemAudioOutput.devices()
            for device in devices {
                let item = NSMenuItem(title: device.name, action: #selector(selectDevice(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = NSNumber(value: device.id)
                item.state = device.id == current ? .on : .off
                item.image = NSImage(systemSymbolName: device.symbol, accessibilityDescription: nil)
                menu.addItem(item)
            }
            if devices.isEmpty {
                let empty = NSMenuItem(title: "暂无可用输出设备", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
            }
            menu.addItem(.separator())
            let settings = NSMenuItem(title: "AirPlay 与声音设置…", action: #selector(openSoundSettings), keyEquivalent: "")
            settings.target = self
            menu.addItem(settings)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
            if selectionError != nil {
                let alert = NSAlert()
                alert.messageText = "未能切换播放设备"
                alert.informativeText = "设备可能已断开。请重新连接后选择，或前往声音设置。"
                alert.addButton(withTitle: "好")
                alert.runModal()
            }
        }

        @objc private func selectDevice(_ item: NSMenuItem) {
            guard let device = item.representedObject as? NSNumber else { return }
            let status = SystemAudioOutput.select(device.uint32Value)
            if status != noErr { selectionError = status }
        }

        @objc private func openSoundSettings() {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Sound.prefPane"))
        }
    }
}
