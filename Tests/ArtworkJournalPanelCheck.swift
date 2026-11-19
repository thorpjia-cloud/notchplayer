import AppKit

@main enum Check {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let limit = 400
        let current = directory.appendingPathComponent("artwork.log")
        let previous = directory.appendingPathComponent("artwork.previous.log")
        let first = ArtworkJournal(directory: directory, limit: limit)
        first.mark("listener_start")
        first.mark("view_default", channel: "view")
        first.mark("view_default", channel: "view")
        first.mark("view_image", channel: "view")
        first.flush()
        let initial = try String(contentsOf: current, encoding: .utf8)
        precondition(initial.split(separator: "\n").count == 3)
        let restarted = ArtworkJournal(directory: directory, limit: limit)
        restarted.mark("listener_start")
        restarted.flush()
        let afterRestart = try String(contentsOf: current, encoding: .utf8)
        precondition(afterRestart.components(separatedBy: "listener_start").count == 3)
        for idx in 0..<25 { restarted.mark("test_rotation", "event=\(idx)") }
        restarted.flush()
        for file in [current, previous] {
            let data = try Data(contentsOf: file)
            precondition(data.count <= limit && !data.isEmpty && data.last == 10)
        }
        let unwritable = ArtworkJournal(directory: current)
        unwritable.mark("non_fatal")
        unwritable.flush()

        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ExpandedPanelSettings(defaults: defaults)
        precondition(settings.style == .system && settings.style.appearance == nil)
        settings.style = .dark
        precondition(ExpandedPanelSettings(defaults: defaults).style.appearance?.name == .darkAqua)
        settings.style = .light
        precondition(ExpandedPanelSettings(defaults: defaults).style.appearance?.name == .aqua)
        settings.style = .system
        precondition(ExpandedPanelSettings(defaults: defaults).style == .system)
        print("PASS journal deduplication, relaunch append, rotation, safe I/O failure and appearance persistence")
    }
}
