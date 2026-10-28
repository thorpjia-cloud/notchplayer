import Foundation

@main enum ArtworkStateCheck {
    static func main() {
        func song(_ title: String, _ art: String? = nil, album: String = "Album", source: String = "player") -> [String: Any] {
            var data: [String: Any] = ["title": title, "artist": "Artist", "album": album, "bundleIdentifier": source, "playing": true]
            if let art { data["artworkData"] = art }
            return data
        }
        var state = ArtworkState()
        state.receive(song("A", "cover-A"), now: 0)
        state.receive([:], now: 1)
        precondition(state.artwork == "cover-A" && state.expiresAt == 1.5)
        state.receive([:], now: 1.4)
        precondition(state.expiresAt == 1.5, "Empty updates must not postpone expiry")
        state.expire(now: 1.5)
        precondition(state.artwork == nil)
        state.receive(song("A", "cover-A"), now: 2)
        state.receive([:], now: 3)
        state.receive(song("A", "cover-A"), now: 3.2)
        state.expire(now: 3.5)
        precondition(state.artwork == "cover-A" && state.expiresAt == nil, "Recovered metadata cancels expiry")
        var paused = song("A", "cover-A"); paused["playing"] = false
        state.receive(paused, now: 4)
        state.expire(now: 400)
        precondition(state.artwork == "cover-A", "Pause alone cannot expire artwork")
        state.receive(song("B"), now: 401)
        precondition(state.artwork == nil && state.expiresAt == nil, "A new track with no image clears immediately")
        state.receive(song("B", "cover-A"), now: 402)
        precondition(state.artwork == "cover-A", "Tracks on the same album may share artwork")
        state.receive(song("C", "cover-A", album: "Other"), now: 403)
        precondition(state.artwork == nil, "A new album must reject the previous image")
        state.receive(song("C", "cover-A", album: "Other"), now: 404)
        precondition(state.artwork == nil)
        state.receive(song("C", "cover-C", album: "Other"), now: 405)
        precondition(state.artwork == "cover-C")
        state.receive(song("D", "cover-D", album: "Next"), now: 406)
        precondition(state.artwork == "cover-D", "A fresh cover can arrive with the new track")
        state.receive(song("D" , album: "Next"), now: 407)
        state.expire(now: 407.5)
        precondition(state.artwork == nil, "Missing image with a valid title also expires")
        state.receive(song("D", "cover-D", album: "Next"), now: 408)
        state.receive(song("D", "cover-D", album: "Next", source: "other-player"), now: 409)
        precondition(state.artwork == nil, "Player changes cannot borrow old artwork")
        state = ArtworkState()
        state.receive(song("D", "cover-D", album: "Next"), now: 410)
        precondition(state.artwork == "cover-D", "Reconnect accepts a new snapshot")
        print("PASS artwork gap deadline, recovery, pause, track changes, stale cross-album image, shared album, player switch and reset")
    }
}
