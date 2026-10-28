import Foundation

// Artwork has a shorter lifetime than the playback session: gaps must not hide the controls.
struct ArtworkState {
    struct Track: Equatable {
        let source: String
        let id: String?
        let title: String
        let artist: String
        let album: String

        init?(_ payload: [String: Any]) {
            guard let title = payload["title"] as? String, !title.isEmpty else { return nil }
            self.title = title
            source = (payload["parentApplicationBundleIdentifier"] as? String)
                ?? (payload["bundleIdentifier"] as? String) ?? ""
            id = (payload["contentItemIdentifier"] as? String)
                ?? (payload["uniqueIdentifier"] as? String)
            artist = payload["artist"] as? String ?? ""
            album = payload["album"] as? String ?? ""
        }

        func sharesAlbum(with other: Track) -> Bool {
            source == other.source && !album.isEmpty && album == other.album
                && !artist.isEmpty && artist == other.artist
        }
    }

    private(set) var track: Track?
    private(set) var artwork: String?
    private(set) var expiresAt: TimeInterval?
    private var lastArtwork: String?
    private var rejectedArtwork: String?

    mutating func receive(_ payload: [String: Any], now: TimeInterval) {
        expire(now: now)
        guard let next = Track(payload) else { beginGap(now: now); return }
        let changed = track != next
        if changed {
            // Some players publish a new title with the previous album's image still attached.
            if let previous = track, !next.sharesAlbum(with: previous) {
                rejectedArtwork = lastArtwork
            } else { rejectedArtwork = nil }
            artwork = nil
            expiresAt = nil
            track = next
        }
        if let encoded = payload["artworkData"] as? String, !encoded.isEmpty,
           encoded != rejectedArtwork {
            artwork = encoded
            lastArtwork = encoded
            rejectedArtwork = nil
            expiresAt = nil
        } else if !changed {
            beginGap(now: now)
        }
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
