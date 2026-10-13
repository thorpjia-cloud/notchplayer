import Foundation
import Combine
import CoreAudio
import AudioToolbox

final class OutputVolume: ObservableObject {
    @Published private(set) var value: Double = 0
    @Published private(set) var available = false
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var selector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
    private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }
    func refresh() {
        var output = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var current = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &output, 0, nil, &size, &current) == noErr else {
            available = false; return
        }
        device = current
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
            value = muted != 0 ? 0 : Double(scalar)
            available = true
            return
        }
        // HDMI and fixed-level outputs must not expose a slider that cannot change sound.
        available = false
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
        value = Double(scalar)
    }
}
