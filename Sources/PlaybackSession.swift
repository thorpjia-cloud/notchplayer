import Foundation

struct PlaybackSession {
    private(set) var processID: Int32?
    var isActive: Bool { processID != nil }

    mutating func observe(processID: Int32?, hasTrack: Bool, playing: Bool) {
        guard let processID, hasTrack, playing || isActive else { return }
        // A started session survives pauses and incomplete metadata between tracks.
        self.processID = processID
    }

    @discardableResult
    mutating func processDidExit(_ processID: Int32) -> Bool {
        guard self.processID == processID else { return false }
        self.processID = nil
        return true
    }
}
