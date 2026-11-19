import AppKit
import Foundation
import ImageIO
import SQLite3

final class HighResolutionArtwork {
    private var task: Task<Void, Never>?
    private let database: URL?
    private let session: URLSession
    init(database: URL? = nil, session: URLSession = .shared) { self.database = database; self.session = session }
    private static let cache: NSCache<NSString, NSData> = {
        let c = NSCache<NSString, NSData>(); c.countLimit = 24; c.totalCostLimit = 16 * 1024 * 1024; return c
    }()
    func cancel() { task?.cancel(); task = nil }

    func resolve(track: ArtworkState.Track, reference: Data, duration: Double, completion: @escaping (Data) -> Void) {
        cancel()
        guard track.source == "com.netease.163music", Self.pixels(reference) < 312 else { return }
        let database = self.database
        task = Task { @MainActor in
            let candidates = await Task.detached(priority: .utility) { Self.sources(track: track, duration: duration, database: database) }.value
            guard !Task.isCancelled else { return }
            for url in candidates {
                do {
                    let data: Data
                    if let cached = Self.cache.object(forKey: url.absoluteString as NSString) { data = cached as Data }
                    else {
                        var request = URLRequest(url: url); request.timeoutInterval = 8
                        let (download, response) = try await session.data(for: request)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                              let final = http.url, Self.trusted(final), download.count <= 10 * 1024 * 1024 else { continue }
                        data = download
                    }
                    guard !Task.isCancelled else { return }
                    let matches = await Task.detached(priority: .utility) {
                        Self.pixels(data) >= 312 && Self.sameArtwork(data, reference)
                    }.value
                    guard !Task.isCancelled, matches else { continue }
                    Self.cache.setObject(data as NSData, forKey: url.absoluteString as NSString, cost: data.count)
                    completion(data); return
                } catch { if Task.isCancelled { return } }
            }
        }
    }
    static func pixels(_ data: Data) -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return 0 }
        return min(p[kCGImagePropertyPixelWidth] as? Int ?? 0, p[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }
    static func trusted(_ url: URL) -> Bool {
        url.scheme == "https" && (url.host?.hasSuffix(".music.126.net") == true) && url.user == nil && url.password == nil
    }
    // Compare actual image content as well as track metadata before accepting a provider URL.
    static func sameArtwork(_ a: Data, _ b: Data) -> Bool {
        func sample(_ data: Data) -> [UInt8]? {
            guard let s = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(s, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 32, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
            var bytes = [UInt8](repeating: 0, count: 16 * 16 * 4)
            let ok = bytes.withUnsafeMutableBytes { p -> Bool in
                guard let c = CGContext(data: p.baseAddress, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                c.interpolationQuality = .high; c.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16)); return true
            }
            return ok ? bytes : nil
        }
        guard let x = sample(a), let y = sample(b) else { return false }
        let error = x.indices.filter { $0 % 4 != 3 }.reduce(0.0) { $0 + abs(Double(x[$1]) - Double(y[$1])) }
        return error / Double(16 * 16 * 3 * 255) < 0.065
    }
    static func sources(track: ArtworkState.Track, duration: Double, database: URL? = nil) -> [URL] {
        let albums = matchingAlbums(track: track, duration: duration, database: database, verifyIdentity: false)
        let urls = (albums ?? []).compactMap { album -> URL? in
            guard let raw = album["picUrl"] as? String, var components = URLComponents(string: raw) else { return nil }
            components.scheme = "https"; components.query = "param=600y600"; components.fragment = nil
            guard let url = components.url, trusted(url) else { return nil }
            return url
        }
        return Set(urls).sorted { $0.absoluteString < $1.absoluteString }
    }

    enum AlbumComparison: String {
        case same, different, unverified
    }

    func compareAlbums(for handoff: ArtworkState.AlbumHandoff) async -> AlbumComparison {
        let database = self.database
        return await Task.detached(priority: .utility) {
            Self.compareAlbums(for: handoff, database: database)
        }.value
    }

    static func compareAlbums(for handoff: ArtworkState.AlbumHandoff, database: URL? = nil) -> AlbumComparison {
        func albumID(for recording: ArtworkState.AlbumTrack) -> String? {
            guard let albums = matchingAlbums(track: recording.track, duration: recording.duration,
                                              database: database, verifyIdentity: true),
                  !albums.isEmpty else { return nil }
            let ids = albums.compactMap { album -> String? in
                let id = String(describing: album["id"] ?? "")
                return !id.isEmpty && id != "0" && id.allSatisfy(\.isNumber) ? id : nil
            }
            guard ids.count == albums.count, Set(ids).count == 1 else { return nil }
            return ids.first
        }
        guard let previous = albumID(for: handoff.previous), let current = albumID(for: handoff.current) else {
            return .unverified
        }
        return previous == current ? .same : .different
    }

    private static func matchingAlbums(track: ArtworkState.Track, duration: Double, database: URL?,
                                       verifyIdentity: Bool) -> [[String: Any]]? {
        let location = database ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.netease.163music/Documents/storage/sqlite_storage.sqlite3")
        var db: OpaquePointer?
        guard sqlite3_open_v2(location.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else { if db != nil { sqlite3_close(db) }; return [] }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)
        let deadline = UnsafeMutablePointer<TimeInterval>.allocate(capacity: 1)
        deadline.initialize(to: Date.timeIntervalSinceReferenceDate + 0.4)
        sqlite3_progress_handler(db, 1000, { pointer in
            guard let pointer else { return 1 }
            return Date.timeIntervalSinceReferenceDate > pointer.assumingMemoryBound(to: TimeInterval.self).pointee ? 1 : 0
        }, deadline)
        defer { sqlite3_progress_handler(db, 0, nil, nil); deadline.deinitialize(count: 1); deadline.deallocate() }
        var matches: [[String: Any]] = []
        let id = verifyIdentity ? track.providerTrackID : track.id
        let trackID = id.flatMap { !$0.isEmpty && $0.allSatisfy(\.isNumber) ? $0 : nil }
        guard !track.artist.isEmpty, duration > 0 || (verifyIdentity && trackID != nil) else { return nil }
        // Album identity uses each recording's exact title, artist and duration (or stable ID).
        // The reported album name can still be the previous song's, so it is not an identity filter.
        for (table, ordering, limit) in [("historyTracks", " ORDER BY playtime DESC", 16), ("dbTrack", "", 24)] {
            let query = "SELECT jsonStr FROM \(table) WHERE json_extract(jsonStr, '$.name') = ?\(ordering) LIMIT \(limit)"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                if verifyIdentity { return nil }
                continue
            }
            defer { sqlite3_finalize(statement) }
            _ = track.title.withCString { sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            var rows = 0
            var status = sqlite3_step(statement)
            while status == SQLITE_ROW {
                rows += 1
                defer { status = sqlite3_step(statement) }
                guard let text = sqlite3_column_text(statement, 0), let data = String(cString: text).data(using: .utf8),
                      let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      item["name"] as? String == track.title,
                      let album = item["album"] as? [String: Any],
                      let artists = item["artists"] as? [[String: Any]],
                      artists.compactMap({ $0["name"] as? String }).joined(separator: "/") == track.artist,
                      let milliseconds = item["duration"] as? NSNumber,
                      duration <= 0 || abs(milliseconds.doubleValue / 1000 - duration) < 2 else { continue }
                if let trackID, String(describing: item["id"] ?? "") != trackID { continue }
                if !verifyIdentity {
                    guard !track.album.isEmpty, album["name"] as? String == track.album,
                          let raw = album["picUrl"] as? String, var url = URLComponents(string: raw) else { continue }
                    url.scheme = "https"
                    guard let candidate = url.url, trusted(candidate) else { continue }
                }
                matches.append(album)
            }
            if verifyIdentity {
                // A capped or interrupted scan cannot establish that the match is unique.
                if status != SQLITE_DONE || rows == limit { return nil }
            } else if !matches.isEmpty { break }
        }
        return matches
    }
}
