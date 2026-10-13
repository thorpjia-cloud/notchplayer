import Foundation
import Combine
import CoreAudio
import AudioToolbox

final class OutputVolume: ObservableObject {
    @Published private(set) var value: Double = 0
    @Published private(set) var available = false
    @Published private(set) var outputName = "未连接设备"
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var selector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
    private struct Listener {
        var object: AudioObjectID
        var address: AudioObjectPropertyAddress
        var block: AudioObjectPropertyListenerBlock
    }
    private var systemListeners: [Listener] = []
    private var deviceListeners: [Listener] = []
    private var observing = false

    func start() {
        guard !observing else { return }
        observing = true
        let output = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                               mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        if let listener = listen(to: AudioObjectID(kAudioObjectSystemObject), at: output) {
            systemListeners.append(listener)
        }
        refresh()
    }

    private func listen(to object: AudioObjectID, at property: AudioObjectPropertyAddress) -> Listener? {
        var property = property
        guard AudioObjectHasProperty(object, &property) else { return nil }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.observing else { return }
            self.refresh()
        }
        guard AudioObjectAddPropertyListenerBlock(object, &property, .main, block) == noErr else { return nil }
        return Listener(object: object, address: property, block: block)
    }

    private func remove(_ listeners: inout [Listener]) {
        for var listener in listeners {
            AudioObjectRemovePropertyListenerBlock(listener.object, &listener.address, .main, listener.block)
        }
        listeners.removeAll()
    }

    func stop() {
        observing = false
        remove(&deviceListeners); remove(&systemListeners)
        device = AudioObjectID(kAudioObjectUnknown)
    }

    deinit { stop() }

    private func publish(value: Double? = nil, available: Bool) {
        if let value, self.value != value { self.value = value }
        if self.available != available { self.available = available }
    }
    private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }
    func refresh() {
        var output = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var current = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &output, 0, nil, &size, &current) == noErr else {
            publish(available: false); return
        }
        if device != current {
            remove(&deviceListeners)
            device = current
            let name = SystemAudioOutput.name(of: device)
            if outputName != name { outputName = name }
            // Rebind when speakers/headphones change; volume and mute otherwise arrive as events.
            if observing {
                for property in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
                    if let listener = listen(to: device, at: address(property)) { deviceListeners.append(listener) }
                }
            }
        }
        for candidate in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar] {
            var property = address(candidate)
            var writable: DarwinBoolean = false
            var scalar: Float32 = 0
            size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectHasProperty(device, &property),
                  AudioObjectIsPropertySettable(device, &property, &writable) == noErr, writable.boolValue,
                  AudioObjectGetPropertyData(device, &property, 0, nil, &size, &scalar) == noErr else { continue }
            selector = candidate
            var mute = address(kAudioDevicePropertyMute)
            var muted: UInt32 = 0
            size = UInt32(MemoryLayout<UInt32>.size)
            _ = AudioObjectGetPropertyData(device, &mute, 0, nil, &size, &muted)
            publish(value: muted != 0 ? 0 : Double(scalar), available: true)
            return
        }
        // HDMI and fixed-level outputs must not expose a slider that cannot change sound.
        publish(available: false)
    }
    func set(_ newValue: Double) {
        refresh()
        guard available else { return }
        var property = address(selector)
        var scalar = Float32(min(1, max(0, newValue)))
        guard AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar) == noErr else {
            refresh(); return
        }
        var mute = address(kAudioDevicePropertyMute)
        var writable: DarwinBoolean = false
        if AudioObjectIsPropertySettable(device, &mute, &writable) == noErr, writable.boolValue {
            var muted: UInt32 = scalar == 0 ? 1 : 0
            _ = AudioObjectSetPropertyData(device, &mute, 0, nil, UInt32(MemoryLayout<UInt32>.size), &muted)
        }
        publish(value: Double(scalar), available: true)
    }
}
