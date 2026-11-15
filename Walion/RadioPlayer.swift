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
    private(set) var error: String?

    private let player = AVPlayer()
    private var statusTask: Task<Void, Never>?

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
        let item = AVPlayerItem(url: current.url)
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        error = nil

        statusTask?.cancel()
        statusTask = Task { [weak self] in
            for await status in item.publisher(for: \.status).values where status == .failed {
                self?.error = item.error?.localizedDescription ?? "Playback failed"
                self?.stop()
            }
        }
    }

    func stop() {
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
                    Text(player.error ?? (player.isPlaying ? "Live" : "Stopped"))
                        .font(.caption)
                        .foregroundStyle(player.error == nil ? Color.secondary : Color.red)
                        .lineLimit(1)
                }
                Spacer()
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
