import Foundation

@main enum PlaybackSessionCheck {
    static func main() {
        var session = PlaybackSession()
        session.observe(processID: 101, hasTrack: true, playing: false)
        precondition(!session.isActive, "An idle player must not reveal the notch before playback")
        session.observe(processID: nil, hasTrack: true, playing: true)
        precondition(!session.isActive, "Stale media without a running player cannot open the notch")

        session.observe(processID: 101, hasTrack: true, playing: true)
        precondition(session.isActive && session.processID == 101)
        session.observe(processID: 101, hasTrack: true, playing: false)
        precondition(session.isActive, "Pausing must keep the visible player available")
        session.observe(processID: nil, hasTrack: false, playing: false)
        session.observe(processID: 202, hasTrack: false, playing: false)
        precondition(session.processID == 101, "Incomplete track handoffs must retain the session")
        precondition(!session.processDidExit(202) && session.isActive, "Unrelated apps cannot hide music")

        session.observe(processID: 202, hasTrack: true, playing: true)
        precondition(!session.processDidExit(101) && session.processID == 202,
                     "Quitting the old player after handoff cannot hide the new player")
        precondition(session.processDidExit(202) && !session.isActive)
        session.observe(processID: 303, hasTrack: true, playing: true)
        precondition(session.isActive && session.processID == 303, "Playback after exit must reveal again")
        print("PASS idle launch, pause retention, metadata gaps, app exit, player handoff, new session")
    }
}
