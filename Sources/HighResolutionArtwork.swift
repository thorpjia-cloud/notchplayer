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
        var urls = Set<URL>()
        // Restrict the lookup to track metadata; never inspect accounts, cookies, or credentials.
        for query in ["SELECT jsonStr FROM historyTracks WHERE json_extract(jsonStr, '$.name') = ? ORDER BY playtime DESC LIMIT 16",
                      "SELECT jsonStr FROM dbTrack WHERE json_extract(jsonStr, '$.name') = ? LIMIT 24"] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(statement) }
            if sqlite3_bind_parameter_count(statement) > 0 {
                _ = track.title.withCString { sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            }
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let text = sqlite3_column_text(statement, 0), let data = String(cString: text).data(using: .utf8),
                      let v = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      v["name"] as? String == track.title, let album = v["album"] as? [String: Any],
                      !track.album.isEmpty, album["name"] as? String == track.album,
                      let artists = v["artists"] as? [[String: Any]],
                      artists.compactMap({ $0["name"] as? String }).joined(separator: "/") == track.artist,
                      let ms = v["duration"] as? NSNumber, duration > 0, abs(ms.doubleValue / 1000 - duration) < 2 else { continue }
                if let id = track.id, id.allSatisfy(\.isNumber), !id.isEmpty, String(describing: v["id"] ?? "") != id { continue }
                guard let raw = album["picUrl"] as? String, var components = URLComponents(string: raw) else { continue }
                components.scheme = "https"; components.query = "param=600y600"; components.fragment = nil
                if let url = components.url, trusted(url) { urls.insert(url) }
            }
            if !urls.isEmpty { break }
        }
        return urls.sorted { $0.absoluteString < $1.absoluteString }
    }
}
