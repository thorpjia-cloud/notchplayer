import Foundation

// Artwork has a shorter lifetime than the playback session: gaps must not hide the controls.
struct ArtworkState {
    struct Track: Equatable {
        static let netEaseSource = "com.netease.163music"
        let source: String
        let id: String?
        private let uniqueID: String?
        var providerTrackID: String? { uniqueID.flatMap { $0.allSatisfy(\.isNumber) ? $0 : nil } }
        let title: String
        let artist: String
        let album: String

        init?(_ payload: [String: Any], previous: Track? = nil) {
            guard let title = Self.text(payload["title"]) else { return nil }
            let previous = previous.flatMap { $0.title == title && $0.matchesHints(in: payload) ? $0 : nil }
            self.title = title
            source = Self.reportedSource(payload) ?? previous?.source ?? ""
            if source == Self.netEaseSource {
                // NetEase rotates the content item ID during pause and resume. Keep the
                // original lookup ID while the stable identity and song metadata agree.
                uniqueID = Self.text(payload["uniqueIdentifier"]) ?? previous?.uniqueID
                id = uniqueID ?? previous?.id ?? Self.reportedID(payload)
            } else {
                uniqueID = nil
                id = Self.reportedID(payload) ?? previous?.id
            }
            artist = Self.text(payload["artist"]) ?? previous?.artist ?? ""
            album = Self.text(payload["album"]) ?? previous?.album ?? ""
        }

        fileprivate static func reportedSource(_ payload: [String: Any]) -> String? {
            text(payload["parentApplicationBundleIdentifier"]) ?? text(payload["bundleIdentifier"])
        }

        fileprivate static func reportedID(_ payload: [String: Any]) -> String? {
            text(payload["contentItemIdentifier"]) ?? text(payload["uniqueIdentifier"])
        }

        private static func text(_ value: Any?) -> String? {
            guard let value = value as? String, !value.isEmpty else { return nil }
            return value
        }

        fileprivate func matchesHints(in payload: [String: Any]) -> Bool {
            func agrees(_ known: String?, _ reported: String?) -> Bool {
                known == nil || known == "" || reported == nil || known == reported
            }
            let agreesWithID = source == Self.netEaseSource
                ? agrees(uniqueID, Self.text(payload["uniqueIdentifier"]))
                : agrees(id, Self.reportedID(payload))
            return agrees(source, Self.reportedSource(payload))
                && agreesWithID
                && agrees(artist, Self.text(payload["artist"]))
                && agrees(album, Self.text(payload["album"]))
        }

        func sharesAlbum(with other: Track) -> Bool {
            source == other.source && !album.isEmpty && album == other.album
                && !artist.isEmpty && artist == other.artist
        }

        fileprivate func matchesRecoverySnapshot(_ payload: [String: Any]) -> Bool {
            guard let snapshot = Track(payload) else { return false }
            return snapshot.source == source && snapshot.title == title
                && (artist.isEmpty || snapshot.artist == artist)
                && (album.isEmpty || snapshot.album == album)
                && (uniqueID == nil || snapshot.uniqueID == uniqueID)
        }
    }

    private(set) var track: Track?
    private(set) var generation = UUID()
    private(set) var artwork: String?
    private(set) var expiresAt: TimeInterval?
    var isAwaitingReplacement: Bool { artwork == nil && expiresAt != nil }
    private var lastArtwork: String?
    struct AlbumTrack: Equatable {
        let track: Track
        let duration: Double
    }
    struct AlbumHandoff: Equatable {
        let previous: AlbumTrack
        let current: AlbumTrack
        let encoded: String
    }
    private var lastArtworkTrack: AlbumTrack?
    private var duration: Double = 0
    private(set) var albumHandoff: AlbumHandoff?
    private var rejectedArtwork: String?

    mutating func receive(_ payload: [String: Any], now: TimeInterval) {
        guard let next = Track(payload, previous: track) else {
            if let track, !track.matchesHints(in: payload) {
                generation = UUID()
                ArtworkJournal.shared.mark("stream_reject", "titleless_conflicting_identity", channel: "stream")
                rejectedArtwork = lastArtwork
                artwork = nil
                expiresAt = nil
                self.track = nil
                albumHandoff = nil
            } else {
                ArtworkJournal.shared.mark("stream_keep", "titleless_compatible", channel: "stream")
                // A sparse snapshot without conflicting identity can follow a valid cover.
                // Honor an existing handoff or disconnect deadline without starting a new one.
                expire(now: now)
            }
            return
        }
        let changed = track.map { $0.title != next.title || !$0.matchesHints(in: payload) } ?? true
        if changed {
            ArtworkJournal.shared.track += 1
            ArtworkJournal.shared.mark("identity_changed", "source_changed=\(track?.source != next.source) title_changed=\(track?.title != next.title) id_changed=\(track?.id != next.id) album_changed=\(track?.album != next.album) artist_changed=\(track?.artist != next.artist)")
            generation = UUID()
            albumHandoff = nil
            duration = 0
            // Invalidate the old request immediately. The view may keep its last image briefly
            // while the same player supplies artwork for the new identity.
            let canBridge = track?.source == next.source && !next.source.isEmpty
            let deadline = canBridge ? expiresAt ?? artwork.map { _ in now + 0.5 } : nil
            if let previous = track {
                let canReuse = next.source != Track.netEaseSource && next.sharesAlbum(with: previous)
                rejectedArtwork = canReuse ? nil : lastArtwork
            }
            artwork = nil
            expiresAt = deadline
        } else if artwork != nil {
            expiresAt = nil
        }
        track = next
        if let micros = (payload["durationMicros"] as? NSNumber)?.doubleValue, micros > 0 {
            duration = micros / 1_000_000
        }
        if let encoded = payload["artworkData"] as? String, !encoded.isEmpty {
            if encoded != rejectedArtwork {
                let decision = artwork == encoded ? "unchanged" : "new_image"
                ArtworkJournal.shared.mark("stream_accept", "\(decision) same_as_rejected=false", channel: "stream")
                acceptArtwork(encoded)
            } else {
                ArtworkJournal.shared.mark("stream_reject", "previous_image same_as_rejected=true", channel: "stream")
                considerSharedArtwork(encoded)
            }
        } else {
            ArtworkJournal.shared.mark("stream_reject", "missing_image same_as_rejected=false", channel: "stream")
        }
        expire(now: now)
    }

    @discardableResult
    mutating func recoverArtwork(from snapshot: [String: Any], previouslyObserved: String? = nil) -> Bool {
        // A first read can pair new metadata with the departing artwork. A later
        // identity-checked read can confirm that the player still assigns it to this track.
        guard artwork == nil, expiresAt == nil, let track, track.matchesRecoverySnapshot(snapshot),
              let encoded = snapshot["artworkData"] as? String, !encoded.isEmpty,
              encoded != rejectedArtwork || encoded == previouslyObserved else { return false }
        acceptArtwork(encoded)
        return true
    }

    func recoveryReturnedPreviousArtwork(_ snapshot: [String: Any]) -> Bool {
        guard artwork == nil, expiresAt == nil, let track, track.matchesRecoverySnapshot(snapshot),
              let rejectedArtwork else { return false }
        return snapshot["artworkData"] as? String == rejectedArtwork
    }

    mutating func considerSharedArtwork(_ encoded: String) {
        guard artwork == nil, encoded == rejectedArtwork, let track, let previous = lastArtworkTrack,
              track.source == Track.netEaseSource, previous.track.source == track.source else { return }
        albumHandoff = AlbumHandoff(previous: previous, current: AlbumTrack(track: track, duration: duration), encoded: encoded)
    }

    mutating func acceptSharedArtwork(_ handoff: AlbumHandoff) -> Bool {
        guard albumHandoff == handoff, track == handoff.current.track, artwork == nil,
              rejectedArtwork == handoff.encoded else { return false }
        acceptArtwork(handoff.encoded)
        return true
    }

    private mutating func acceptArtwork(_ encoded: String) {
        artwork = encoded
        lastArtwork = encoded
        lastArtworkTrack = track.map { AlbumTrack(track: $0, duration: duration) }
        albumHandoff = nil
        // Keep the rejection through this track so a late packet cannot restore the prior image.
        expiresAt = nil
    }

    mutating func beginGap(now: TimeInterval) {
        // A disconnected adapter starts a deadline even if the last cover is still visible.
        if artwork != nil && expiresAt == nil { expiresAt = now + 0.5 }
    }

    mutating func expire(now: TimeInterval) {
        if let deadline = expiresAt, now >= deadline {
            artwork = nil
            expiresAt = nil
        }
    }
}
