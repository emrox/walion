import SwiftUI

/// Bottom bar on every screen: station, what is on air, loading, sleep timer, play/stop.
struct NowPlayingBar: View {
    @Environment(RadioPlayer.self) private var player

    var body: some View {
        if let station = player.current {
            HStack {
                StationLogo(url: station.logo)
                VStack(alignment: .leading) {
                    Text(station.name).lineLimit(1)
                    Text(player.error ?? (player.isLoading ? "Loading…" : player.isPlaying ? player.streamTitle ?? "Live" : "Stopped"))
                        .font(.caption)
                        .foregroundStyle(player.error == nil ? Color.secondary : Color.red)
                        .lineLimit(1)
                }
                Spacer()
                if player.isLoading {
                    ProgressView().controlSize(.small)
                }
                if player.isPlaying {
                    SleepTimerMenu()
                }
                Button(player.isPlaying ? "Stop" : "Play",
                       systemImage: player.isPlaying ? "stop.fill" : "play.fill") {
                    player.toggle()
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
