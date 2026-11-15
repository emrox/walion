import AVFoundation
import SwiftUI

/// Plays one live radio stream at a time. Shared app-wide via the environment.
@Observable
final class RadioPlayer {
    struct Station: Equatable {
        let id: String
        let name: String
        let url: URL
    }

    private(set) var current: Station?
    private(set) var isPlaying = false
    /// Connecting or rebuffering.
    private(set) var isLoading = false
    private(set) var error: String?

    private let player = AVPlayer()
    // KVO tokens. Not `publisher(for:).values`: that only ever delivers the initial value here.
    @ObservationIgnored private var loadingObservation: NSKeyValueObservation?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    init() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        #endif
        loadingObservation = player.observe(\.timeControlStatus) { @Sendable [weak self] player, _ in
            let loading = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            DispatchQueue.main.async { self?.isLoading = loading }
        }
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
        let item = AVPlayerItem(url: current.url)
        statusObservation = item.observe(\.status) { @Sendable [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "Playback failed"
            DispatchQueue.main.async {
                self?.stop()
                self?.error = message
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        error = nil
    }

    func stop() {
        player.pause()  // otherwise the player keeps "waiting" for an item
        player.replaceCurrentItem(with: nil)
        isPlaying = false
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
