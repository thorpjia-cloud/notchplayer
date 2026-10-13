import Foundation
import Combine

@main enum PlaybackProgressCheck {
    static func main() {
        let progress = PlaybackProgress()
        var changes = 0
        let subscription = progress.$position.dropFirst().sink { _ in changes += 1 }
        let timestamp = Date()
        progress.update(elapsed: 20, timestamp: timestamp, rate: 1, duration: 100, playing: true, available: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        precondition(changes == 0, "Hidden progress must not publish timer updates")

        progress.setVisible(true)
        precondition(progress.position >= 20.3 && progress.position < 22, "Opening must catch up immediately")
        let openedChanges = changes
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        precondition(changes > openedChanges, "Visible playback must advance")

        progress.update(elapsed: 37, timestamp: Date(), rate: 0, duration: 100, playing: false, available: true)
        let pausedChanges = changes
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        precondition(progress.position == 37 && changes == pausedChanges, "Pause must stop redundant updates")

        progress.setVisible(false)
        progress.update(elapsed: 42, timestamp: Date(), rate: 0, duration: 100, playing: false, available: true)
        precondition(changes == pausedChanges, "Hidden metadata must not wake the slider")
        progress.setVisible(true)
        precondition(progress.position == 42, "Reopening a paused/seeked track must show its new position")

        progress.update(elapsed: 98, timestamp: timestamp, rate: 1, duration: 100, playing: true, available: true)
        progress.refresh(now: timestamp.addingTimeInterval(10))
        precondition(progress.position == 100, "Progress must remain within track duration")
        progress.update(elapsed: 0, timestamp: Date(), rate: 0, duration: 0, playing: false, available: false)
        precondition(progress.position == 0, "An unavailable player must clear progress")
        progress.stop()
        withExtendedLifetime(subscription) {}
        print("PASS hidden/visible clock, pause, seek/reopen, duration clamp, unavailable player")
    }
}
