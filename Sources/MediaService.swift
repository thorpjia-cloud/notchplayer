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
    private let highResolutionArtwork: HighResolutionArtwork
    private var highResolutionTrack: ArtworkState.Track?
    private var highResolutionDuration: Double = 0
    private var hasHighResolution = false
    init(highResolutionArtwork: HighResolutionArtwork = HighResolutionArtwork()) { self.highResolutionArtwork = highResolutionArtwork }
    private var artworkToken: String?
    private var artworkState = ArtworkState()
    private var artworkExpiry: DispatchWorkItem?
    private var journalDeadline: TimeInterval?
    private var journalTimer = 0
    private var journalRecovery = 0
    private let journal = ArtworkJournal.shared
    private var checkedAlbumHandoff: ArtworkState.AlbumHandoff?
    private var albumLookup: Task<Void, Never>?
    private var artworkRecoveryTrack: ArtworkState.Track?
    private var artworkRecoveryID = UUID()
    private var artworkRecoveryAfter: TimeInterval = 0
    private var artworkQuery: Process?
    private var connectionID = UUID()
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
    private var listenerRetries = 0
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
        listenerRetries = 0
        volume.start()
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  self.session.processDidExit(app.processIdentifier) else { return }
            self.assign(\.sessionActive, false)
            self.journal.mark("player_exit")
            self.clearPlayback()
        }
        startListener()
    }
    private func startListener() {
        journal.session += 1
        journal.mark("listener_start")
        let connection = UUID()
        let launchedAt = ProcessInfo.processInfo.systemUptime
        connectionID = connection
        buffer.removeAll()
        let process = makeProcess(["stream", "--no-diff", "--micros", "--debounce=100"])
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async {
                guard let self, self.connectionID == connection, !self.stopped else { return }
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
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self, self.connectionID == connection, !self.stopped,
                      self.stream === process else { return }
                self.stream = nil
                if ProcessInfo.processInfo.systemUptime - launchedAt >= 10 { self.listenerRetries = 0 }
                self.journal.mark("listener_disconnect", "status=\(process.terminationStatus)")
                self.artworkState.beginGap(now: ProcessInfo.processInfo.systemUptime)
                self.refreshArtwork()
                self.error = "音乐连接已断开，请从菜单重新连接"
                self.retryListener(after: connection)
            }
        }
        do { try process.run(); stream = process }
        catch {
            journal.mark("listener_start_failed")
            self.error = "无法连接系统正在播放"
            retryListener(after: connection)
        }
        // Re-arm the existing deadline against the new connection, without extending it.
        if artworkState.expiresAt != nil { refreshArtwork() }
    }
    private func retryListener(after connection: UUID) {
        guard listenerRetries < 3 else { return }
        listenerRetries += 1
        journal.mark("listener_retry", "attempt=\(listenerRetries)")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250 * listenerRetries)) { [weak self] in
            guard let self, !self.stopped, self.connectionID == connection, self.stream == nil else { return }
            self.startListener()
        }
    }
    func stop() {
        journal.mark("listener_stop")
        stopped = true
        connectionID = UUID()
        resetArtwork()
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
    func apply(_ value: [String: Any]) {
        if let processID = session.processID,
           NSRunningApplication(processIdentifier: processID)?.isTerminated != false {
            journal.mark("player_process_gone")
            session.processDidExit(processID)
            assign(\.sessionActive, false)
        }
        guard let title = value["title"] as? String, !title.isEmpty else {
            // A metadata gap is not a stopped player; keep its controls and timeline usable.
            if !session.isActive { clearPlayback() }
            else {
                artworkState.receive(value, now: ProcessInfo.processInfo.systemUptime)
                refreshArtwork()
            }
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
        artworkState.receive(value, now: ProcessInfo.processInfo.systemUptime)
        refreshArtwork()
        progress.update(elapsed: elapsed, timestamp: timestamp, rate: rate, duration: duration, playing: playing, available: available)
        let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            ?? (value["processIdentifier"] as? NSNumber).flatMap { NSRunningApplication(processIdentifier: $0.int32Value) }
        session.observe(processID: application?.processIdentifier, hasTrack: true, playing: playing)
        assign(\.sessionActive, session.isActive)
    }
    private func clearPlayback() {
        assign(\.playing, false); assign(\.available, false)
        assign(\.title, "还没有正在播放的音乐"); assign(\.artist, "在你喜欢的播放器中播放一首歌")
        assign(\.album, ""); assign(\.duration, 0); resetArtwork()
        progress.update(elapsed: 0, timestamp: Date(), rate: 0, duration: duration, playing: false, available: false)
        spectrum.update(bundleID: nil, playing: false)
    }
    private func resetArtwork() {
        if artworkState.track != nil || artwork != nil {
            journal.mark("artwork_reset")
            journal.track += 1
        }
        if journalDeadline != nil { journal.mark("timer_cancel", "id=\(journalTimer) reset") }
        journalDeadline = nil
        highResolutionArtwork.cancel()
        albumLookup?.cancel()
        albumLookup = nil
        checkedAlbumHandoff = nil
        cancelArtworkRecovery()
        artworkExpiry?.cancel(); artworkExpiry = nil
        artworkState = ArtworkState()
        highResolutionTrack = nil; highResolutionDuration = 0; hasHighResolution = false
        updateArtwork(nil)
    }
    private func refreshArtwork() {
        defer { scheduleArtworkRecoveryIfNeeded() }
        verifySharedArtworkIfNeeded()
        artworkExpiry?.cancel(); artworkExpiry = nil
        if artworkState.isAwaitingReplacement && artwork != nil {
            // Keep only the already-rendered image. The old request has no current artwork token.
            highResolutionArtwork.cancel()
        } else {
            updateArtwork(artworkState.artwork)
        }
        if journalDeadline != artworkState.expiresAt {
            if journalDeadline != nil { journal.mark("timer_cancel", "id=\(journalTimer)") }
            journalDeadline = artworkState.expiresAt
            if journalDeadline != nil {
                journalTimer += 1
                journal.mark("timer_create", "id=\(journalTimer)")
            }
        }
        guard let deadline = artworkState.expiresAt else { return }
        let timer = journalTimer
        let connection = connectionID
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped, self.connectionID == connection,
                  self.artworkState.expiresAt == deadline else { return }
            self.journal.mark("timer_fire", "id=\(timer)")
            self.journalDeadline = nil
            self.artworkState.expire(now: ProcessInfo.processInfo.systemUptime)
            self.refreshArtwork()
        }
        artworkExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - ProcessInfo.processInfo.systemUptime), execute: work)
    }
    private func verifySharedArtworkIfNeeded() {
        let handoff = artworkState.albumHandoff
        guard handoff != checkedAlbumHandoff else { return }
        albumLookup?.cancel()
        checkedAlbumHandoff = handoff
        guard let handoff else { albumLookup = nil; return }
        let connection = connectionID
        albumLookup = Task { @MainActor [weak self, highResolutionArtwork] in
            let comparison = await highResolutionArtwork.compareAlbums(for: handoff)
            if !Task.isCancelled, let self, self.connectionID == connection, self.artworkState.albumHandoff == handoff {
                self.journal.mark("album_id_compare", "result=\(comparison.rawValue)", channel: "album")
            }
            guard !Task.isCancelled, let self, !self.stopped, self.connectionID == connection,
                  self.artworkState.albumHandoff == handoff,
                  comparison == .same, self.artworkState.acceptSharedArtwork(handoff) else { return }
            self.journal.mark("shared_album_cover_accept")
            self.refreshArtwork()
        }
    }
    private func cancelArtworkRecovery() {
        if artworkRecoveryTrack != nil { journal.mark("recovery_cancel", "id=\(journalRecovery)") }
        artworkRecoveryID = UUID()
        artworkRecoveryAfter = 0
        if artworkQuery?.isRunning == true { artworkQuery?.terminate() }
        artworkQuery = nil
        artworkRecoveryTrack = nil
    }
    private func scheduleArtworkRecoveryIfNeeded() {
        let track = artworkState.track
        if artworkRecoveryTrack != track { cancelArtworkRecovery() }
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= artworkRecoveryAfter, artworkQuery == nil, let track, track.source == ArtworkState.Track.netEaseSource,
              artworkState.artwork == nil, artworkState.expiresAt == nil, stream?.isRunning == true else {
            if track?.source == ArtworkState.Track.netEaseSource, artworkState.artwork == nil {
                let reason = artworkRecoveryTrack != nil ? "cooldown_or_query_active" : artworkState.expiresAt != nil ? "handoff_pending" : "listener_unavailable"
                journal.mark("recovery_skip", reason, channel: "recovery")
            }
            return
        }
        journalRecovery += 1
        let query = journalRecovery
        journal.mark("recovery_schedule", "id=\(query)", channel: "recovery")
        // A later stream update may re-arm a failed recovery without polling an idle player.
        artworkRecoveryAfter = now + 30
        artworkRecoveryID = UUID()
        artworkRecoveryTrack = track
        let connection = connectionID
        let recovery = artworkRecoveryID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            guard self.connectionID == connection, self.artworkRecoveryID == recovery,
                  self.artworkState.track == track, self.artworkState.artwork == nil,
                  self.stream?.isRunning == true else {
                self.journal.mark("recovery_skip", "id=\(query) scheduled_query_invalidated")
                return
            }
            self.queryArtwork(for: track, connection: connection)
        }
    }
    private func queryArtwork(for track: ArtworkState.Track, connection: UUID, previouslyObserved: String? = nil) {
        let generation = artworkState.generation
        let process = makeProcess(["get", "--micros"])
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let query = journalRecovery
        do { try process.run() } catch { journal.mark("recovery_failed", "id=\(query) launch"); return }
        journal.mark("recovery_start", "id=\(query) retry=\(previouslyObserved != nil)")
        artworkQuery = process
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if process.isRunning {
                self?.journal.mark("recovery_timeout", "id=\(query)")
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let snapshot = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                func reject(_ reason: String) { self.journal.mark("recovery_reject", "id=\(query) \(reason)") }
                guard self.artworkQuery === process else { reject("superseded"); return }
                self.artworkQuery = nil
                guard process.terminationStatus == 0 else { reject("process_exit status=\(process.terminationStatus)"); return }
                guard self.connectionID == connection, self.artworkState.generation == generation, self.artworkState.track == track else { reject("track_or_connection_changed"); return }
                guard let snapshot else { reject("no_snapshot"); return }
                guard let pid = self.session.processID, NSRunningApplication(processIdentifier: pid)?.isTerminated == false else { reject("no_live_session"); return }
                guard (snapshot["processIdentifier"] as? NSNumber)?.int32Value == pid else { reject("player_pid_mismatch"); return }
                guard let encoded = snapshot["artworkData"] as? String else { reject("no_image"); return }
                guard let data = Data(base64Encoded: encoded), NSImage(data: data) != nil else { reject("invalid_image"); return }
                let previousImage = self.artworkState.recoveryReturnedPreviousArtwork(snapshot)
                guard self.artworkState.recoverArtwork(from: snapshot, previouslyObserved: previouslyObserved) else {
                    reject(previousImage ? "previous_image same_as_rejected=true" : (self.artworkState.artwork == nil ? "identity_or_handoff_guard same_as_rejected=unverified" : "already_has_image"))
                    if previousImage {
                        self.artworkState.considerSharedArtwork(encoded)
                        self.verifySharedArtworkIfNeeded()
                        if previouslyObserved == nil {
                            self.journal.mark("recovery_retry_scheduled", "id=\(query)")
                            self.retryArtworkQuery(for: track, connection: connection, observed: encoded)
                        }
                    }
                    return
                }
                self.journal.mark("recovery_accept", "id=\(query) same_as_rejected=\(previousImage) repeated_live_confirmation=\(previousImage && previouslyObserved == encoded)")
                self.refreshArtwork()
            }
        }
    }
    private func retryArtworkQuery(for track: ArtworkState.Track, connection: UUID, observed: String) {
        let recovery = artworkRecoveryID
        let generation = artworkState.generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.connectionID == connection, self.artworkRecoveryID == recovery,
                  self.artworkState.generation == generation,
                  self.artworkState.track == track, self.artworkState.artwork == nil,
                  self.artworkState.expiresAt == nil, self.artworkQuery == nil,
                  self.stream?.isRunning == true else { return }
            self.queryArtwork(for: track, connection: connection, previouslyObserved: observed)
        }
    }
    private func updateArtwork(_ encoded: String?) {
        let imageChanged = encoded != artworkToken
        let track = artworkState.track
        guard imageChanged || track != highResolutionTrack || abs(duration - highResolutionDuration) > 0.1 else { return }
        highResolutionArtwork.cancel()
        highResolutionTrack = track; highResolutionDuration = duration
        if !imageChanged && hasHighResolution { return }
        artworkToken = encoded
        hasHighResolution = false
        guard let encoded, let data = Data(base64Encoded: encoded), let image = NSImage(data: data) else {
            journal.mark("cover_default", encoded == nil ? "no_accepted_image" : "decode_failed", channel: "cover")
            artwork = nil; artworkColors = ArtworkPalette.fallback
            return
        }
        journal.mark("cover_thumbnail", "image_changed=\(imageChanged)", channel: "cover")
        artwork = image
        artworkColors = ArtworkPalette.colors(from: image)
        guard let track else { return }
        let generation = artworkState.generation
        highResolutionArtwork.resolve(track: track, reference: data, duration: duration) { [weak self] highData in
            guard let self, self.artworkState.generation == generation, self.artworkState.track == track,
                  self.artworkState.artwork == encoded,
                  let highImage = NSImage(data: highData) else {
                self?.journal.mark("high_resolution_reject", "stale_or_decode_failed", channel: "high")
                return
            }
            self.hasHighResolution = true
            self.journal.mark("cover_high_resolution", channel: "cover")
            self.artwork = highImage
            // Palette remains based on the stable system thumbnail; resolution upgrades do not flash the tint.
        }
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
