import AVFoundation
import SwiftUI

/// Plays one live radio stream at a time. Shared app-wide via the environment.
///
/// Every (re)start gets a fresh muted `AVPlayer`. The stream already playing keeps
/// going until the new one actually produces audio, then they swap. If the new one
/// fails, the old one just keeps playing.
@Observable
final class RadioPlayer {
    struct Station: Equatable {
        let id: String
        let name: String
        let url: URL
    }

    private(set) var current: Station?
    private(set) var isPlaying = false
    /// Connecting, switching or rebuffering.
    private(set) var isLoading = false
    private(set) var error: String?

    /// The stream you hear.
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var playerStation: Station?
    /// The stream being loaded, muted until it plays.
    @ObservationIgnored private var next: AVPlayer?
    // KVO tokens. Not `publisher(for:).values`: that only ever delivers the initial value here.
    @ObservationIgnored private var playerObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private var nextObservations: [NSKeyValueObservation] = []

    init() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        #endif
    }

    func play(_ channel: Channel) {
        guard let url = URL(string: channel.streamURL) else {
            error = "Invalid stream URL"
            return
        }
        current = Station(id: channel.stationID, name: channel.name, url: url)
        resume()
    }

    /// Live radio: always reconnect instead of un-pausing a stale buffer.
    func resume() {
        guard let current else { return }
        dropNext()
        let item = AVPlayerItem(url: current.url)
        let loading = AVPlayer(playerItem: item)
        loading.isMuted = true
        let changed: @Sendable (Any, Any) -> Void = { [weak self] _, _ in
            DispatchQueue.main.async { self?.update() }
        }
        nextObservations = [
            loading.observe(\.timeControlStatus, changeHandler: changed),
            item.observe(\.status, changeHandler: changed),
        ]
        next = loading
        loading.play()
        isPlaying = true
        error = nil
        update()
    }

    func stop() {
        dropNext()
        player?.pause()
        player = nil
        playerStation = nil
        playerObservations = []
        isPlaying = false
        isLoading = false
    }

    private func dropNext() {
        next?.pause()
        next = nil
        nextObservations = []
    }

    /// Runs on every status change of either player.
    private func update() {
        if let item = next?.currentItem, item.status == .failed {
            let reason = item.error?.localizedDescription ?? "Playback failed"
            if player == nil {
                stop()
                error = reason
            } else {
                error = "Couldn't play \(current?.name ?? "station"): \(reason)"
                dropNext()
                current = playerStation
            }
        }
        if let item = player?.currentItem, item.status == .failed {
            let reason = item.error?.localizedDescription ?? "Playback failed"
            stop()
            error = reason
        }
        if let loaded = next, loaded.timeControlStatus == .playing {
            player?.pause()
            loaded.isMuted = false
            player = loaded
            playerStation = current
            playerObservations = nextObservations
            next = nil
            nextObservations = []
        }
        isLoading = next != nil || player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
    }
}

struct NowPlayingBar: View {
    @Environment(RadioPlayer.self) private var player

    var body: some View {
        if let station = player.current {
            HStack {
                VStack(alignment: .leading) {
                    Text(station.name).lineLimit(1)
                    Text(player.error ?? (player.isLoading ? "Loading…" : player.isPlaying ? "Live" : "Stopped"))
                        .font(.caption)
                        .foregroundStyle(player.error == nil ? Color.secondary : Color.red)
                        .lineLimit(1)
                }
                Spacer()
                if player.isLoading {
                    ProgressView().controlSize(.small)
                }
                Button(player.isPlaying ? "Stop" : "Play",
                       systemImage: player.isPlaying ? "stop.fill" : "play.fill") {
                    player.isPlaying ? player.stop() : player.resume()
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .buttonStyle(.plain)
            }
            .padding()
            .background(.bar)
        }
    }
}
