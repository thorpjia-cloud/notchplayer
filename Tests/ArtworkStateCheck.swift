import Foundation

@main enum ArtworkStateCheck {
    static func main() {
        func song(_ title: String, _ art: String? = nil, album: String = "Album", source: String = "player") -> [String: Any] {
            var data: [String: Any] = ["title": title, "artist": "Artist", "album": album, "bundleIdentifier": source, "playing": true]
            if let art { data["artworkData"] = art }
            return data
        }
        var state = ArtworkState()
        // Replay the captured order: new cover, pause/resume, then an incomplete snapshot.
        state.receive(song("A", "cover-A"), now: 0)
        state.receive(song("B", album: "Other"), now: 0.2)
        state.receive(song("B", "cover-B", album: "Other"), now: 0.31)
        var pausedB = song("B", "cover-B", album: "Other")
        pausedB["playing"] = false
        state.receive(pausedB, now: 1)
        state.receive(song("B", "cover-B", album: "Other"), now: 1.07)
        state.receive(["bundleIdentifier": "player", "playing": true], now: 1.1)
        state.expire(now: 1.63)
        guard state.artwork == "cover-B", state.expiresAt == nil else {
            FileHandle.standardError.write(Data("FAIL: Incomplete snapshot cleared the confirmed replacement cover\n".utf8))
            exit(1)
        }

        state = ArtworkState()
        var netease = song("E", "cover-E", album: "", source: "com.netease.163music")
        netease["contentItemIdentifier"] = "item-1"
        state.receive(netease, now: 10)
        let initialTrack = state.track
        netease["playing"] = false
        state.receive(netease, now: 11)
        netease["contentItemIdentifier"] = "item-2"
        state.receive(netease, now: 11.11)
        state.expire(now: 11.64)
        guard state.artwork == "cover-E", state.track == initialTrack, state.expiresAt == nil else {
            FileHandle.standardError.write(Data("FAIL: NetEase pause changed only the item identifier and cleared the cover\n".utf8))
            exit(1)
        }
        netease["contentItemIdentifier"] = "item-3"
        netease["artworkData"] = nil
        state.receive(netease, now: 11.81)
        state.expire(now: 12.4)
        precondition(state.artwork == "cover-E", "An artwork-free identifier refresh also keeps the confirmed cover")
        netease["artworkData"] = "cover-E"
        state.receive(netease, now: 12.5)
        netease["playing"] = true
        netease["contentItemIdentifier"] = "item-4"
        state.receive(netease, now: 400)
        precondition(state.artwork == "cover-E" && state.track == initialTrack, "Resume can rotate the item identifier again")
        netease["uniqueIdentifier"] = "song-E"
        state.receive(netease, now: 401)
        netease["uniqueIdentifier"] = "song-E-edition"
        netease["artworkData"] = nil
        state.receive(netease, now: 402)
        precondition(state.artwork == nil, "A different stable identifier must invalidate a lookalike track")
        netease["artworkData"] = "cover-E-edition"
        state.receive(netease, now: 402.1)
        state.receive(song("F", "cover-E-edition", album: "New", source: "com.netease.163music"), now: 403)
        precondition(state.artwork == nil && state.isAwaitingReplacement, "A true song change rejects the old thumbnail")
        state.receive(song("F", "cover-F", album: "New", source: "com.netease.163music"), now: 403.1)
        state.expire(now: 403.5)
        precondition(state.artwork == "cover-F", "The old deadline must not clear a confirmed replacement")

        let nextCover = song("G", "cover-F", album: "Compilation", source: "com.netease.163music")
        state.receive(song("G", album: "Compilation", source: "com.netease.163music"), now: 404)
        state.receive(nextCover, now: 404.12)
        precondition(!state.recoverArtwork(from: nextCover), "Finish the normal stream handoff before recovery")
        state.expire(now: 404.5)
        state.receive(nextCover, now: 405)
        precondition(state.artwork == nil, "A new album can receive delayed artwork from the prior track")
        precondition(!state.recoverArtwork(from: song("F", "cover-F", album: "New", source: "com.netease.163music")))
        precondition(!state.recoverArtwork(from: song("G", "cover-F", album: "Compilation", source: "other-player")))
        precondition(!state.recoverArtwork(from: song("G", "cover-F", album: "New", source: "com.netease.163music")))
        guard !state.recoverArtwork(from: nextCover), state.artwork == nil else {
            FileHandle.standardError.write(Data("FAIL: Recovery accepted the prior album's rejected cover\n".utf8))
            exit(1)
        }
        precondition(state.recoveryReturnedPreviousArtwork(nextCover))
        precondition(!state.recoveryReturnedPreviousArtwork(song("F", "cover-F", album: "New", source: "com.netease.163music")))
        let correctCover = song("G", "cover-G", album: "Compilation", source: "com.netease.163music")
        precondition(state.recoverArtwork(from: correctCover) && state.artwork == "cover-G",
                     "A matching current snapshot recovers a fresh cover")
        state.receive(nextCover, now: 405.2)
        precondition(state.artwork == "cover-G", "A late prior cover must not overwrite the recovered cover")
        precondition(!state.recoveryReturnedPreviousArtwork(nextCover), "A confirmed cover ends the retry path")
        precondition(!state.recoverArtwork(from: song("G", "other-cover", album: "Compilation", source: "com.netease.163music")),
                     "A late query cannot replace a cover already confirmed by the stream")

        // The live reads agreed before the local album record became available.
        state = ArtworkState()
        state.receive(song("F", "shared-cover", album: "Compilation", source: ArtworkState.Track.netEaseSource), now: 0)
        var current = song("G", album: "Compilation", source: ArtworkState.Track.netEaseSource)
        current["artist"] = "Guest"
        state.receive(current, now: 1)
        current["artworkData"] = "shared-cover"
        state.receive(current, now: 1.12)
        state.expire(now: 1.5)
        precondition(!state.recoverArtwork(from: current))
        var wrongTrack = current
        wrongTrack["title"] = "F"
        precondition(!state.recoverArtwork(from: wrongTrack, previouslyObserved: "shared-cover"))
        precondition(!state.recoverArtwork(from: current, previouslyObserved: "other-cover"))
        precondition(state.recoverArtwork(from: current, previouslyObserved: "shared-cover"))
        precondition(state.artwork == "shared-cover")
        var fresh = current
        fresh["artworkData"] = "fresh-cover"
        state.receive(fresh, now: 4)
        state.receive(current, now: 4.1)
        precondition(state.artwork == "fresh-cover", "Repeated prior artwork must not displace a fresh stream image")
        let generation = state.generation
        state.receive(wrongTrack, now: 5)
        state.receive(current, now: 6)
        precondition(state.generation != generation, "Returning to the same recording creates a new generation")

        state = ArtworkState()
        state.receive(song("A", "cover-A"), now: 0)
        state.beginGap(now: 1)
        precondition(state.artwork == "cover-A" && state.expiresAt == 1.5)
        state.receive([:], now: 1.4)
        precondition(state.expiresAt == 1.5, "Empty updates must not postpone expiry")
        state.expire(now: 1.5)
        precondition(state.artwork == nil)
        state.receive(song("A", "cover-A"), now: 2)
        state.beginGap(now: 3)
        state.receive(song("A", "cover-A"), now: 3.2)
        state.expire(now: 3.5)
        precondition(state.artwork == "cover-A" && state.expiresAt == nil, "Recovered metadata cancels expiry")
        var paused = song("A", "cover-A"); paused["playing"] = false
        state.receive(paused, now: 4)
        state.expire(now: 400)
        precondition(state.artwork == "cover-A", "Pause alone cannot expire artwork")
        state.receive(song("B"), now: 401)
        precondition(state.artwork == nil && state.isAwaitingReplacement && state.expiresAt == 401.5,
                     "Invalidate the old track image immediately and bound the visual handoff")
        state.receive(song("B"), now: 401.2)
        precondition(state.expiresAt == 401.5, "Repeated handoff snapshots cannot extend the deadline")
        state.receive([:], now: 401.3)
        state.expire(now: 401.5)
        precondition(state.artwork == nil && state.expiresAt == nil, "A known track change still expires on time")
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
        var sparsePause = song("D")
        sparsePause["album"] = nil
        sparsePause["artist"] = nil
        sparsePause["playing"] = false
        state.receive(sparsePause, now: 407)
        precondition(state.artwork == "cover-D", "Paused update missing artwork and optional metadata retains the cover")
        state.receive([:], now: 407.2)
        state.expire(now: 407.8)
        precondition(state.artwork == "cover-D", "A paused session tolerates a transient empty snapshot")
        state.receive(song("D", album: "Next"), now: 407.9)
        state.expire(now: 408.5)
        precondition(state.artwork == "cover-D", "Resume with the same title and no image retains the cover")
        state.receive(song("D", "cover-D", album: "Next"), now: 408.6)
        state.receive(song("D", "cover-D", album: "Next", source: "other-player"), now: 409)
        precondition(state.artwork == nil && !state.isAwaitingReplacement, "Player changes cannot borrow old artwork")
        state = ArtworkState()
        precondition(state.artwork == nil, "Session reset clears the current cover")
        var firstEdition = song("D", "cover-D", album: "Next")
        firstEdition["contentItemIdentifier"] = "edition-1"
        state.receive(song("D", "cover-D", album: "Next"), now: 410)
        firstEdition["artworkData"] = nil
        state.receive(firstEdition, now: 410.5)
        precondition(state.artwork == "cover-D", "A newly reported identifier enriches the current track")
        var secondEdition = song("D", album: "Next")
        secondEdition["contentItemIdentifier"] = "edition-2"
        state.receive(secondEdition, now: 411)
        precondition(state.artwork == nil, "Matching title cannot keep the old cover when the track identifier changes")
        state = ArtworkState()
        state.receive(song("D", "cover-D", album: "Next"), now: 412)
        precondition(state.artwork == "cover-D", "Reconnect accepts a new snapshot")
        state = ArtworkState()
        let sameAlbumSource = "com.netease.163music"
        state.receive(song("A", "shared", source: sameAlbumSource), now: 0)
        state.receive(song("B", source: sameAlbumSource), now: 1)
        state.expire(now: 1.5)
        let sharedCover = song("B", "shared", source: sameAlbumSource)
        precondition(state.recoveryReturnedPreviousArtwork(sharedCover))
        state.receive(sharedCover, now: 1.6)
        let proof = state.albumHandoff!
        precondition(state.acceptSharedArtwork(proof) && state.artwork == "shared")
        state.receive(song("C", album: "Other", source: sameAlbumSource), now: 2)
        precondition(!state.acceptSharedArtwork(proof) && state.artwork == nil,
                     "Album proof cannot cross a track change")
        print("PASS replacement cover survives incomplete updates; disconnect and handoff deadlines, pause, track and player changes")
    }
}
