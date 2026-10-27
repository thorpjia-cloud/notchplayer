import AppKit
import Accelerate
import CoreAudio

// A short, overlapping FFT keeps bass resolution without visibly delaying transients.
final class SpectrumAnalyzer {
    static let count = 2048
    static let ranges: [ClosedRange<Double>] = [60...160, 160...400, 400...1000, 1000...2500, 2500...6300, 6300...16000]
    private let sampleRate: Double
    private let setup = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2))!
    private var window = [Float](repeating: 0, count: count)
    private var ring = [[Float]](repeating: [Float](repeating: 0, count: count), count: 2)
    private var work = [Float](repeating: 0, count: count)
    private var real = [Float](repeating: 0, count: count / 2)
    private var imaginary = [Float](repeating: 0, count: count / 2)
    private var power = [Float](repeating: 0, count: count / 2)
    private var cursor = 0
    private var received = 0
    private var hop = 0
    private var normalization: Float = 1
    private let lock = NSLock()
    private var latest = [Float](repeating: 0, count: SpectrumAnalyzer.ranges.count)
    private var lastFrame: TimeInterval = 0
    private(set) var receivedSignal = false

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        vDSP_hann_window(&window, vDSP_Length(Self.count), Int32(vDSP_HANN_NORM))
        normalization = 1 / (2 * Float(Self.count) * window.reduce(0) { $0 + $1 * $1 })
    }
    deinit { vDSP_destroy_fftsetup(setup) }

    func push(left: Float, right: Float) {
        ring[0][cursor] = left.isFinite ? left : 0
        ring[1][cursor] = right.isFinite ? right : 0
        cursor = (cursor + 1) % Self.count
        received += 1; hop += 1
        if received >= Self.count && hop >= 512 {
            hop = 0
            analyze()
        }
    }
    func consume(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let data = first.mData else { return }
        let channels = Int(first.mNumberChannels)
        guard channels > 0 else { return }
        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channels
        let samples = data.assumingMemoryBound(to: Float.self)
        if channels >= 2 {
            for i in 0..<frames { push(left: samples[i * channels], right: samples[i * channels + 1]) }
        } else if buffers.count > 1, let rightData = buffers[1].mData {
            let right = rightData.assumingMemoryBound(to: Float.self)
            let rightChannels = max(1, Int(buffers[1].mNumberChannels))
            let rightFrames = Int(buffers[1].mDataByteSize) / MemoryLayout<Float>.size / rightChannels
            for i in 0..<min(frames, rightFrames) { push(left: samples[i], right: right[i * rightChannels]) }
        } else {
            for i in 0..<frames { push(left: samples[i], right: samples[i]) }
        }
    }
    private func analyze() {
        for k in power.indices { power[k] = 0 }
        for channel in 0..<2 {
            for i in 0..<Self.count { work[i] = ring[channel][(cursor + i) % Self.count] * window[i] }
            real.withUnsafeMutableBufferPointer { r in
                imaginary.withUnsafeMutableBufferPointer { im in
                    var split = DSPSplitComplex(realp: r.baseAddress!, imagp: im.baseAddress!)
                    work.withUnsafeBufferPointer { input in
                        input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.count / 2) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(Self.count / 2))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, 11, FFTDirection(FFT_FORWARD))
                    // Sum channel power separately: opposite-phase stereo must not cancel.
                    for k in 1..<Self.count / 2 { power[k] += (r[k] * r[k] + im[k] * im[k]) * 0.5 * normalization }
                }
            }
        }
        let levels = Self.ranges.map { range -> Float in
            let lower = max(1, Int(ceil(range.lowerBound * Double(Self.count) / sampleRate)))
            let upper = min(Self.count / 2, Int(ceil(range.upperBound * Double(Self.count) / sampleRate)))
            guard lower < upper else { return 0 }
            let energy = power[lower..<upper].reduce(0, +)
            let decibels = 10 * log10(max(energy, 1e-12))
            // A fixed dB scale preserves actual relative band energy; no per-band auto gain.
            return max(0, min(1, (decibels + 60) / 54))
        }
        if !receivedSignal && levels.contains(where: { $0 > 0.02 }) {
            receivedSignal = true
            NSLog("notchplayer spectrum: received non-silent PCM")
        }
        lock.lock(); latest = levels; lastFrame = ProcessInfo.processInfo.systemUptime; lock.unlock()
    }
    func snapshot() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return ProcessInfo.processInfo.systemUptime - lastFrame < 0.25 ? latest : Array(repeating: 0, count: SpectrumAnalyzer.ranges.count)
    }
}

final class AudioSpectrum: ObservableObject {
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0, count: SpectrumAnalyzer.ranges.count)
    @Published private(set) var status = "播放后显示实时频谱：从左到右为低频至高频"
    private var tap: AudioObjectID = 0
    private var device: AudioObjectID = 0
    private var io: AudioDeviceIOProcID?
    private var analyzer: SpectrumAnalyzer?
    private let audioQueue = DispatchQueue(label: "local.nooklab.spectrum", qos: .userInitiated)
    private let captureQueue = DispatchQueue(label: "local.nooklab.capture")
    private var generation = 0
    private var timer: Timer?
    private var activeSource: String?
    private var previousTick = ProcessInfo.processInfo.systemUptime

    func update(bundleID: String?, playing: Bool) {
        let source = playing ? bundleID : nil
        guard source != activeSource else { return }
        activeSource = source
        generation += 1
        let request = generation
        analyzer = nil
        startSmoothing()
        status = source == nil ? "播放已暂停" : "正在连接音频；首次使用请允许系统音频录制"
        // Core Audio can wait for system consent; never block the notch's UI thread.
        captureQueue.async { [weak self] in
            guard let self else { return }
            self.stopCapture()
            guard let source else { return }
            do {
                guard #available(macOS 14.2, *) else {
                    throw CaptureError(operation: "实时频谱需要 macOS 14.2", code: -1)
                }
                let analyzer = try self.startCapture(bundleID: source)
                DispatchQueue.main.async {
                    guard self.generation == request else { return }
                    self.analyzer = analyzer
                    self.status = "六段实时频谱：60–160 Hz · 160–400 Hz · 400–1k Hz · 1–2.5k Hz · 2.5–6.3k Hz · 6.3–16k Hz"
                }
            } catch {
                self.stopCapture()
                NSLog("notchplayer spectrum: %@", String(describing: error))
                DispatchQueue.main.async {
                    guard self.generation == request else { return }
                    self.status = "音频频谱不可用；请检查系统设置中的系统音频录制权限，允许后暂停并重新播放"
                }
            }
        }
    }
    private func startSmoothing() {
        guard timer == nil else { return }
        previousTick = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let dt = min(0.1, now - self.previousTick)
            self.previousTick = now
            let target = self.analyzer?.snapshot() ?? Array(repeating: 0, count: SpectrumAnalyzer.ranges.count)
            let next = self.levels.enumerated().map { i, value -> CGFloat in
                let destination = CGFloat(target[i])
                let tau = destination > value ? 0.035 : 0.18
                let result = value + (destination - value) * CGFloat(1 - exp(-dt / tau))
                return result < 0.001 ? 0 : result
            }
            if next != self.levels { self.levels = next }
            if self.activeSource == nil && self.levels.allSatisfy({ $0 == 0 }) {
                self.timer?.invalidate(); self.timer = nil
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    @available(macOS 14.2, *)
    private func startCapture(bundleID: String) throws -> SpectrumAnalyzer {
        let description = CATapDescription()
        description.name = "notchplayer Music Spectrum"
        description.isPrivate = true
        description.isExclusive = false
        description.isMixdown = true
        description.isMono = false
        description.muteBehavior = .unmuted
        if #available(macOS 26.0, *) {
            description.bundleIDs = [bundleID]
            description.isProcessRestoreEnabled = true
        } else {
            let objects = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).compactMap { app -> AudioObjectID? in
                var pid = app.processIdentifier
                var object: AudioObjectID = 0
                var size = UInt32(MemoryLayout<AudioObjectID>.size)
                var address = Self.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
                let result = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
                return result == noErr && object != 0 ? object : nil
            }
            guard !objects.isEmpty else { throw CaptureError(operation: "查找播放器音频", code: -1) }
            description.processes = objects
        }
        try check(AudioHardwareCreateProcessTap(description, &tap), "创建音频 Tap")
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = Self.address(kAudioTapPropertyFormat)
        try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format), "读取音频格式")
        guard format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 32,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mSampleRate > 0 else {
            throw CaptureError(operation: "不支持的音频格式", code: -1)
        }
        let configuration: [String: Any] = [
            kAudioAggregateDeviceNameKey: "notchplayer Spectrum",
            kAudioAggregateDeviceUIDKey: "local.nooklab.spectrum.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]
        try check(AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &device), "创建频谱输入")
        let analyzer = SpectrumAnalyzer(sampleRate: format.mSampleRate)
        try check(AudioDeviceCreateIOProcIDWithBlock(&io, device, audioQueue) { _, input, _, _, _ in
            analyzer.consume(input)
        }, "接入音频流")
        try check(AudioDeviceStart(device, io), "启动频谱")
        NSLog("notchplayer spectrum: started source=%@ sampleRate=%.0f channels=%u", bundleID, format.mSampleRate, format.mChannelsPerFrame)
        return analyzer
    }
    private func stopCapture() {
        if let io {
            AudioDeviceStop(device, io)
            AudioDeviceDestroyIOProcID(device, io)
        }
        io = nil
        if device != 0 { AudioHardwareDestroyAggregateDevice(device); device = 0 }
        if #available(macOS 14.2, *), tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
    }
    func stop() {
        activeSource = nil; generation += 1; analyzer = nil
        captureQueue.async { [self] in stopCapture() }
        timer?.invalidate(); timer = nil
        levels = Array(repeating: 0, count: SpectrumAnalyzer.ranges.count)
    }
    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private func check(_ code: OSStatus, _ operation: String) throws {
        if code != noErr { throw CaptureError(operation: operation, code: code) }
    }
    private struct CaptureError: Error { let operation: String; let code: OSStatus }
}
