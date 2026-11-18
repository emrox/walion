import Foundation
import MediaPlayer
import Testing
@testable import Walion

/// The player with real AVPlayers on silent audio files. Serialized: Now Playing info is shared.
@Suite("Radio player", .serialized)
struct RadioPlayerTests {
    let player = RadioPlayer()
    let long: URL
    let short: URL  // ends after 2 seconds, like a station closing its stream

    init() throws {
        long = try TestAudio.silence(seconds: 60)
        short = try TestAudio.silence(seconds: 2)
    }

    func station(_ id: String, _ url: URL) throws -> RadioPlayer.Station {
        try #require(RadioPlayer.Station(makeChannel(id, stream: url)))
    }

    func playAndWait(_ id: String, _ url: URL? = nil) async throws {
        player.play(try station(id, url ?? long))
        await waitUntil("\(id) is audible") { player.playing?.id == id && !player.isLoading }
    }

    var nowPlaying: [String: Any] { MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:] }

    // MARK: Playing and switching

    @Test("Playing shows loading first, then the station is audible and on the lock screen")
    func play() async throws {
        defer { player.stop() }
        player.play(try station("A", long))
        #expect(player.current?.id == "A")
        #expect(player.isPlaying)
        #expect(player.isLoading)
        #expect(player.playing == nil)

        await waitUntil("A is audible") { player.playing?.id == "A" && !player.isLoading }
        #expect(nowPlaying[MPMediaItemPropertyTitle] as? String == "A")
        #expect(nowPlaying[MPNowPlayingInfoPropertyIsLiveStream] as? Bool == true)
        #expect(nowPlaying[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1)
    }

    @Test("When switching, the old station plays until the new one is ready")
    func switchStations() async throws {
        defer { player.stop() }
        try await playAndWait("A")

        player.play(try station("B", long))
        #expect(player.current?.id == "B")
        #expect(player.playing?.id == "A")  // still hearing A
        #expect(player.isLoading)

        await waitUntil("B is audible") { player.playing?.id == "B" && !player.isLoading }
        #expect(player.error == nil)
    }

    @Test("If the new station fails, the old one keeps playing and the error names the new one")
    func failedSwitchKeepsOldStation() async throws {
        defer { player.stop() }
        try await playAndWait("A")

        player.play(try station("Broken", TestAudio.missing))
        await waitUntil("the error shows") { player.error != nil }

        #expect(player.current?.id == "A")
        #expect(player.playing?.id == "A")
        #expect(player.isPlaying)
        #expect(player.error?.hasPrefix("Couldn't play Broken") == true)
    }

    @Test("If a station fails with nothing else playing, playback stops with the error")
    func failureWithNothingPlaying() async throws {
        player.play(try station("Broken", TestAudio.missing))
        await waitUntil("the error shows") { player.error != nil }
        #expect(!player.isPlaying)
        #expect(!player.isLoading)
        #expect(player.current?.id == "Broken")
    }

    @Test("Stop ends playback; Play reconnects to the same station")
    func stopAndResume() async throws {
        defer { player.stop() }
        try await playAndWait("A")

        player.toggle()
        #expect(!player.isPlaying)
        #expect(player.playing == nil)
        #expect(nowPlaying[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0)

        player.toggle()
        await waitUntil("A plays again") { player.playing?.id == "A" }
    }

    @Test("Next/previous walk the channel list in order and wrap around")
    func skip() async throws {
        defer { player.stop() }
        player.skip(1)
        #expect(player.current == nil)  // empty list: nothing happens

        player.channels = try ["A", "B", "C"].map { try station($0, long) }
        player.play(player.channels[1])
        var visited: [String] = []
        for offset in [1, 1, -1, -1, -1] {
            player.skip(offset)
            visited.append(player.current?.id ?? "-")
        }
        #expect(visited == ["C", "A", "C", "B", "A"])

        player.play(try station("Removed", long))  // no longer in the list: start at the top
        player.skip(1)
        #expect(player.current?.id == "A")
    }

    @Test("A cached logo goes to the lock screen without a download")
    func cachedArtwork() async throws {
        defer { player.stop() }
        let channel = makeChannel("Logo", stream: long, favicon: "https://logos.test/cached.png")
        channel.logoData = try TestImage.png(width: 64, height: 64)
        player.play(try #require(RadioPlayer.Station(channel)))
        await waitUntil("playing") { player.playing?.id == "Logo" }
        #expect(nowPlaying[MPMediaItemPropertyArtwork] is MPMediaItemArtwork)
    }

    // MARK: Sleep timer

    @Test("The sleep timer stops playback when it runs out")
    func sleepTimerStops() async throws {
        try await playAndWait("A")
        player.setSleepTimer(.seconds(1))
        #expect(player.sleepAt != nil)

        await waitUntil("stopped by the timer", timeout: .seconds(4)) { !player.isPlaying }
        #expect(player.sleepAt == nil)
    }

    @Test("Turning the sleep timer off keeps playing")
    func sleepTimerOff() async throws {
        defer { player.stop() }
        try await playAndWait("A")
        player.setSleepTimer(.seconds(1))
        player.setSleepTimer(nil)
        #expect(player.sleepAt == nil)

        try await Task.sleep(for: .seconds(2))
        #expect(player.isPlaying)
    }

    @Test("Stopping by hand cancels the sleep timer, so it can't stop a later station")
    func stopCancelsSleepTimer() async throws {
        defer { player.stop() }
        try await playAndWait("A")
        player.setSleepTimer(.seconds(1))
        player.stop()
        #expect(player.sleepAt == nil)

        try await playAndWait("B")
        try await Task.sleep(for: .seconds(2))
        #expect(player.isPlaying)
    }

    // MARK: Stopped by the system

    @Test("When the stream stops by itself, the player shows stopped")
    func streamEnds() async throws {
        try await playAndWait("Short", short)
        await waitUntil("stopped after the stream ended", timeout: .seconds(6)) { !player.isPlaying }
        #expect(player.playing == nil)
    }

    @Test("After an interruption that may resume (a call), playback resumes")
    func resumesAfterCall() async throws {
        defer { player.stop() }
        try await playAndWait("Short", short)
        player.handleInterruption(began: true, shouldResume: false)
        await waitUntil("stopped", timeout: .seconds(6)) { !player.isPlaying }

        player.handleInterruption(began: false, shouldResume: true)
        #expect(player.isPlaying)
        #expect(player.current?.id == "Short")
    }

    @Test("Also when iOS announces the interruption just after pausing us")
    func resumesWhenAnnouncedLate() async throws {
        defer { player.stop() }
        try await playAndWait("Short", short)
        await waitUntil("stopped", timeout: .seconds(6)) { !player.isPlaying }

        player.handleInterruption(began: true, shouldResume: false)
        player.handleInterruption(began: false, shouldResume: true)
        #expect(player.isPlaying)
    }

    @Test("An interruption that ends without permission to resume stays stopped")
    func noResumeWithoutPermission() async throws {
        try await playAndWait("Short", short)
        player.handleInterruption(began: true, shouldResume: false)
        await waitUntil("stopped", timeout: .seconds(6)) { !player.isPlaying }

        player.handleInterruption(began: false, shouldResume: false)
        #expect(!player.isPlaying)
    }

    @Test("A call long after the system stopped us (headphones unplugged) doesn't start playback")
    func noResumeAfterOlderStop() async throws {
        try await playAndWait("Short", short)
        await waitUntil("stopped", timeout: .seconds(6)) { !player.isPlaying }
        try await Task.sleep(for: .seconds(2.5))

        player.handleInterruption(began: true, shouldResume: false)
        player.handleInterruption(began: false, shouldResume: true)
        #expect(!player.isPlaying)
    }

    @Test("A call after the user pressed Stop doesn't start playback")
    func noResumeAfterUserStop() async throws {
        try await playAndWait("A")
        player.stop()

        player.handleInterruption(began: true, shouldResume: false)
        player.handleInterruption(began: false, shouldResume: true)
        #expect(!player.isPlaying)
    }
}
