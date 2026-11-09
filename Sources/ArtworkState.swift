import Foundation

// Artwork has a shorter lifetime than the playback session: gaps must not hide the controls.
struct ArtworkState {
    struct Track: Equatable {
        let source: String
        let id: String?
        let title: String
        let artist: String
        let album: String

        init?(_ payload: [String: Any], previous: Track? = nil) {
            guard let title = Self.text(payload["title"]) else { return nil }
            let previous = previous.flatMap { $0.title == title && $0.matchesHints(in: payload) ? $0 : nil }
            self.title = title
            source = Self.reportedSource(payload) ?? previous?.source ?? ""
            id = Self.reportedID(payload) ?? previous?.id
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
            return agrees(source, Self.reportedSource(payload))
                && agrees(id, Self.reportedID(payload))
                && agrees(artist, Self.text(payload["artist"]))
                && agrees(album, Self.text(payload["album"]))
        }

        func sharesAlbum(with other: Track) -> Bool {
            source == other.source && !album.isEmpty && album == other.album
                && !artist.isEmpty && artist == other.artist
        }
    }

    private(set) var track: Track?
    private(set) var artwork: String?
    private(set) var expiresAt: TimeInterval?
    var isAwaitingReplacement: Bool { artwork == nil && expiresAt != nil }
    private var lastArtwork: String?
    private var rejectedArtwork: String?
    private var isPaused = false

    mutating func receive(_ payload: [String: Any], now: TimeInterval) {
        let playing = payload["playing"] as? Bool
        guard let next = Track(payload, previous: track) else {
            if let track, !track.matchesHints(in: payload) {
                rejectedArtwork = lastArtwork
                artwork = nil
                expiresAt = nil
                self.track = nil
                isPaused = false
            } else if let track, playing != true,
                      isPaused || (playing == false && Track.reportedSource(payload) == track.source) {
                // A known paused session may stop reporting metadata until playback resumes.
                isPaused = true
                if artwork != nil { expiresAt = nil }
            } else {
                if playing == true { isPaused = false }
                expire(now: now)
                beginGap(now: now)
            }
            return
        }
        let changed = track.map { $0.title != next.title || !$0.matchesHints(in: payload) } ?? true
        if changed {
            // Invalidate the old request immediately. The view may keep its last image briefly
            // while the same player supplies artwork for the new identity.
            let canBridge = track?.source == next.source && !next.source.isEmpty
            let deadline = canBridge ? expiresAt ?? artwork.map { _ in now + 0.5 } : nil
            if let previous = track {
                rejectedArtwork = next.sharesAlbum(with: previous) ? nil : lastArtwork
            }
            artwork = nil
            expiresAt = deadline
            isPaused = playing == false
        } else {
            if let playing { isPaused = !playing }
            if artwork != nil { expiresAt = nil }
        }
        track = next
        if let encoded = payload["artworkData"] as? String, !encoded.isEmpty,
           encoded != rejectedArtwork {
            artwork = encoded
            lastArtwork = encoded
            rejectedArtwork = nil
            expiresAt = nil
        }
        expire(now: now)
    }

    mutating func beginGap(now: TimeInterval) {
        // Repeated empty updates cannot keep extending the grace period.
        if artwork != nil && expiresAt == nil { expiresAt = now + 0.5 }
    }

    mutating func expire(now: TimeInterval) {
        if let deadline = expiresAt, now >= deadline {
            artwork = nil
            expiresAt = nil
        }
    }
}
