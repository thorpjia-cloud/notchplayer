import AppKit
import Foundation

final class MediaService: ObservableObject {
    let spectrum = AudioSpectrum()
    let volume = OutputVolume()
    let progress = PlaybackProgress()
    @Published var title = "还没有正在播放的音乐"
    @Published var artist = "在你喜欢的播放器中播放一首歌"
    @Published var album = ""
    @Published var source = "系统正在播放"
    @Published var artwork: NSImage?
    @Published private(set) var artworkColors = ArtworkPalette.fallback
    private var artworkToken: String?
    @Published var playing = false
    @Published var available = false
    @Published private(set) var sessionActive = false
    @Published var duration: Double = 0
    @Published var error: String?
    private var bundleID = "com.apple.Music"
    private var elapsed: Double = 0
    private var timestamp = Date()
    private var rate: Double = 1
    private var stream: Process?
    private var buffer = Data()
    private var commands: [Process] = []
    private var stopped = false
    private var session = PlaybackSession()
    private var terminationObserver: NSObjectProtocol?
    private var resources: URL { Bundle.main.resourceURL! }
    private var script: URL { resources.appendingPathComponent("mediaremote-adapter.pl") }
    private var framework: URL { resources.appendingPathComponent("MediaRemoteAdapter.framework") }

    func start() {
        stopped = false
        volume.start()
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  self.session.processDidExit(app.processIdentifier) else { return }
            self.assign(\.sessionActive, false)
            self.clearPlayback()
        }
        let process = makeProcess(["stream", "--no-diff", "--micros", "--debounce=100"])
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.buffer.append(chunk)
                while let newline = self.buffer.firstIndex(of: 10) {
                    let line = self.buffer.prefix(upTo: newline)
                    self.buffer.removeSubrange(...newline)
                    guard let envelope = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                          let payload = envelope["payload"] as? [String: Any] else { continue }
                    self.apply(payload)
                }
            }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, !self.stopped else { return }
                self.error = "音乐连接已断开，请从菜单重新连接"
            }
        }
        do { try process.run(); stream = process }
        catch { self.error = "无法连接系统正在播放" }
    }
    func stop() {
        stopped = true
        if let terminationObserver { NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver) }
        terminationObserver = nil
        spectrum.stop()
        progress.stop()
        volume.stop()
        stream?.terminationHandler = nil
        if stream?.isRunning == true { stream?.terminate() }
        stream = nil; buffer.removeAll()
        commands.filter(\.isRunning).forEach { $0.terminate() }
        commands.removeAll()
    }
    func reconnect() { stop(); error = nil; start() }
    private func makeProcess(_ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, framework.path] + arguments
        return process
    }
    private func apply(_ value: [String: Any]) {
        if let processID = session.processID,
           NSRunningApplication(processIdentifier: processID)?.isTerminated != false {
            session.processDidExit(processID)
            assign(\.sessionActive, false)
        }
        guard let title = value["title"] as? String, !title.isEmpty else {
            // A metadata gap is not a stopped player; keep its controls and timeline usable.
            if !session.isActive { clearPlayback() }
            return
        }
        assign(\.title, title)
        assign(\.artist, value["artist"] as? String ?? "未知歌手")
        assign(\.album, value["album"] as? String ?? "")
        assign(\.playing, value["playing"] as? Bool ?? false)
        assign(\.available, true); assign(\.error, nil)
        let previousBundleID = bundleID
        bundleID = value["parentApplicationBundleIdentifier"] as? String ?? value["bundleIdentifier"] as? String ?? "com.apple.Music"
        spectrum.update(bundleID: bundleID, playing: playing)
        if bundleID != previousBundleID || source == "系统正在播放" {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                assign(\.source, FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
            } else { assign(\.source, "正在播放") }
            if bundleID == "com.apple.Music" { assign(\.source, "Apple Music") }
        }
        assign(\.duration, ((value["durationMicros"] as? NSNumber)?.doubleValue ?? 0) / 1_000_000)
        elapsed = ((value["elapsedTimeMicros"] as? NSNumber)?.doubleValue ?? 0) / 1_000_000
        if let micros = (value["timestampEpochMicros"] as? NSNumber)?.doubleValue {
            timestamp = Date(timeIntervalSince1970: micros / 1_000_000)
        } else { timestamp = Date() }
        rate = (value["playbackRate"] as? NSNumber)?.doubleValue ?? (playing ? 1 : 0)
        if playing && rate == 0 { rate = 1 }
        updateArtwork(value["artworkData"] as? String)
        progress.update(elapsed: elapsed, timestamp: timestamp, rate: rate, duration: duration, playing: playing, available: available)
        let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            ?? (value["processIdentifier"] as? NSNumber).flatMap { NSRunningApplication(processIdentifier: $0.int32Value) }
        session.observe(processID: application?.processIdentifier, hasTrack: true, playing: playing)
        assign(\.sessionActive, session.isActive)
    }
    private func clearPlayback() {
        assign(\.playing, false); assign(\.available, false)
        assign(\.title, "还没有正在播放的音乐"); assign(\.artist, "在你喜欢的播放器中播放一首歌")
        assign(\.album, ""); assign(\.duration, 0); updateArtwork(nil)
        progress.update(elapsed: 0, timestamp: Date(), rate: 0, duration: duration, playing: false, available: false)
        spectrum.update(bundleID: nil, playing: false)
    }
    private func updateArtwork(_ encoded: String?) {
        guard encoded != artworkToken else { return }
        artworkToken = encoded
        guard let encoded, let data = Data(base64Encoded: encoded), let image = NSImage(data: data) else {
            artwork = nil; artworkColors = ArtworkPalette.fallback
            return
        }
        artwork = image
        artworkColors = ArtworkPalette.colors(from: image)
    }
    private func assign<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<MediaService, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
    private func command(_ args: [String]) {
        guard available else { return }
        let process = makeProcess(args)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self else { return }
                self.commands.removeAll { $0 === process }
                if process.terminationStatus != 0 { self.error = "播放器未接受该操作" }
            }
        }
        do { try process.run(); commands.append(process) }
        catch { self.error = "播放控制暂时不可用" }
    }
    func toggle() { command(["send", "2"]) }
    func next() { command(["send", "4"]) }
    func previous() { command(["send", "5"]) }
    func seek(_ seconds: Double) { command(["seek", String(Int(max(0, min(duration, seconds)) * 1_000_000))]) }
    func openPlayer() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
    }
    static func time(_ seconds: Double) -> String {
        let s = max(0, Int(seconds)); return String(format: "%d:%02d", s / 60, s % 60)
    }
}
