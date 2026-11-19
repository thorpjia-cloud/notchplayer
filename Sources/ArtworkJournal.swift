import Foundation

// Main-queue events contain only fixed labels and anonymous counters. Disk I/O is serialized off-main.
final class ArtworkJournal {
    static let shared = ArtworkJournal(directory: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/notchplayer", isDirectory: true))
    var session = 0
    var track = 0
    private var last: [String: String] = [:]
    private let run = String(UUID().uuidString.prefix(8))
    private let start = ProcessInfo.processInfo.systemUptime
    private let queue = DispatchQueue(label: "notchplayer.artwork-journal", qos: .utility)
    private let formatter = ISO8601DateFormatter()
    private let directory: URL
    private let limit: Int

    init(directory: URL, limit: Int = 256 * 1024) {
        self.directory = directory
        self.limit = limit
    }

    func mark(_ event: String, _ detail: String = "", channel: String? = nil) {
        if let channel {
            let value = "\(session)/\(track) \(event) \(detail)"
            guard last[channel] != value else { return }
            last[channel] = value
        }
        let date = Date()
        let elapsed = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
        let line = "run=\(run) ms=\(elapsed) session=\(session) track=\(track) \(event) \(detail)\n"
        queue.async { [self] in
            let data = Data((formatter.string(from: date) + " " + line).utf8)
            try? append(data)
        }
    }

    private func append(_ data: Data) throws {
        guard data.count <= limit else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let current = directory.appendingPathComponent("artwork.log")
        let previous = directory.appendingPathComponent("artwork.previous.log")
        let size = (try? fm.attributesOfItem(atPath: current.path)[.size] as? NSNumber)?.intValue ?? 0
        if size + data.count > limit {
            if fm.fileExists(atPath: previous.path) { try fm.removeItem(at: previous) }
            if size <= limit { try fm.moveItem(at: current, to: previous) }
            else { try fm.removeItem(at: current) }
        }
        if !fm.fileExists(atPath: current.path) {
            guard fm.createFile(atPath: current.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { return }
        }
        let file = try FileHandle(forWritingTo: current)
        defer { try? file.close() }
        try file.seekToEnd()
        try file.write(contentsOf: data)
    }

    // Used by the local diagnostic check to inspect completed writes.
    func flush() { queue.sync {} }
}
