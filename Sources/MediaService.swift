import AppKit
import Foundation

final class MediaService: ObservableObject {
    let spectrum = AudioSpectrum()
    let volume = OutputVolume()
    @Published var title = "还没有正在播放的音乐"
    @Published var artist = "在你喜欢的播放器中播放一首歌"
    @Published var album = ""
    @Published var source = "系统正在播放"
    @Published var artwork: NSImage?
    @Published private(set) var artworkAccent = ArtworkPalette.fallback
    private var artworkToken: String?
    @Published var playing = false
    @Published var available = false
    @Published var duration: Double = 0
    @Published var position: Double = 0
    @Published var error: String?
    private var bundleID = "com.apple.Music"
    private var elapsed: Double = 0
    private var timestamp = Date()
    private var rate: Double = 1
    private var stream: Process?
    private var buffer = Data()
    private var ticker: Timer?
    private var commands: [Process] = []
    private var stopped = false
    private var resources: URL { Bundle.main.resourceURL! }
    private var script: URL { resources.appendingPathComponent("mediaremote-adapter.pl") }
    private var framework: URL { resources.appendingPathComponent("MediaRemoteAdapter.framework") }

    func start() {
        stopped = false
        volume.refresh()
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
        ticker?.invalidate()
        ticker = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.updatePosition(); self?.volume.refresh() }
        RunLoop.main.add(ticker!, forMode: .common)
    }
    func stop() {
        stopped = true
        spectrum.stop()
        stream?.terminationHandler = nil
        if stream?.isRunning == true { stream?.terminate() }
        stream = nil; buffer.removeAll(); ticker?.invalidate()
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
        guard let title = value["title"] as? String, !title.isEmpty else {
            self.title = "还没有正在播放的音乐"; artist = "在你喜欢的播放器中播放一首歌"
            album = ""; playing = false; available = false; updateArtwork(nil)
            duration = 0; position = 0
            spectrum.update(bundleID: nil, playing: false)
            return
        }
        self.title = title
        artist = value["artist"] as? String ?? "未知歌手"
        album = value["album"] as? String ?? ""
        playing = value["playing"] as? Bool ?? false
        available = true; error = nil
        bundleID = value["parentApplicationBundleIdentifier"] as? String ?? value["bundleIdentifier"] as? String ?? "com.apple.Music"
        spectrum.update(bundleID: bundleID, playing: playing)
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            source = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        } else { source = "正在播放" }
        if bundleID == "com.apple.Music" { source = "Apple Music" }
        duration = (value["durationMicros"] as? NSNumber)?.doubleValue ?? 0
        duration /= 1_000_000
        elapsed = ((value["elapsedTimeMicros"] as? NSNumber)?.doubleValue ?? 0) / 1_000_000
        if let micros = (value["timestampEpochMicros"] as? NSNumber)?.doubleValue {
            timestamp = Date(timeIntervalSince1970: micros / 1_000_000)
        } else { timestamp = Date() }
        rate = (value["playbackRate"] as? NSNumber)?.doubleValue ?? (playing ? 1 : 0)
        if playing && rate == 0 { rate = 1 }
        updateArtwork(value["artworkData"] as? String)
        updatePosition()
    }
    private func updateArtwork(_ encoded: String?) {
        guard encoded != artworkToken else { return }
        artworkToken = encoded
        guard let encoded, let data = Data(base64Encoded: encoded), let image = NSImage(data: data) else {
            artwork = nil; artworkAccent = ArtworkPalette.fallback
            return
        }
        artwork = image
        artworkAccent = ArtworkPalette.accent(from: image)
    }
    private func updatePosition() {
        guard available else { return }
        let current = elapsed + (playing ? max(0, Date().timeIntervalSince(timestamp)) * rate : 0)
        position = max(0, duration > 0 ? min(duration, current) : current)
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
