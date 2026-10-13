import Foundation
import Combine

// Progress has its own observation boundary so a ticking slider cannot invalidate the glass panel.
final class PlaybackProgress: ObservableObject {
    @Published private(set) var position: Double = 0
    private var elapsed: Double = 0
    private var timestamp = Date()
    private var rate: Double = 1
    private var duration: Double = 0
    private var playing = false
    private var available = false
    private var visible = false
    private var ticker: Timer?

    func update(elapsed: Double, timestamp: Date, rate: Double, duration: Double, playing: Bool, available: Bool) {
        self.elapsed = elapsed; self.timestamp = timestamp; self.rate = rate
        self.duration = duration; self.playing = playing; self.available = available
        if visible { refresh() }
        updateTimer()
    }

    func setVisible(_ visible: Bool) {
        guard self.visible != visible else { return }
        self.visible = visible
        // Reconstruct from the player's timestamp before the slider appears again.
        if visible { refresh() }
        updateTimer()
    }

    func refresh(now: Date = Date()) {
        let current = elapsed + (playing ? max(0, now.timeIntervalSince(timestamp)) * rate : 0)
        let next = available ? max(0, duration > 0 ? min(duration, current) : current) : 0
        if position != next { position = next }
    }

    private func updateTimer() {
        guard visible && playing && available else {
            ticker?.invalidate(); ticker = nil
            return
        }
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 0.025
        ticker = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() { ticker?.invalidate(); ticker = nil }
    deinit { stop() }
}
