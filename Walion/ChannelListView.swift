import SwiftUI
import SwiftData

struct ChannelListView: View {
    @Environment(\.modelContext) private var context
    @Environment(RadioPlayer.self) private var player
    @Query(sort: \Channel.addedAt) private var channels: [Channel]
    @State private var isSearching = false

    var body: some View {
        List {
            ForEach(channels) { channel in
                ChannelRow(channel: channel)
                    .contextMenu {
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            context.delete(channel)
                        }
                    }
            }
            .onDelete { offsets in
                offsets.map { channels[$0] }.forEach(context.delete)
            }
        }
        .overlay {
            if channels.isEmpty {
                ContentUnavailableView(
                    "No Channels",
                    systemImage: "radio",
                    description: Text("Tap + to search for radio stations.")
                )
            }
        }
        .navigationTitle("Radio Channels")
        .toolbar {
            Button("Add Channel", systemImage: "plus") { isSearching = true }
        }
        .sheet(isPresented: $isSearching) {
            ChannelSearchView()
        }
        .onChange(of: channels, initial: true) {
            player.channels = channels.compactMap(RadioPlayer.Station.init)
        }
    }
}

/// A saved channel; tap to play.
struct ChannelRow: View {
    @Environment(RadioPlayer.self) private var player
    let channel: Channel

    var body: some View {
        Button {
            player.play(channel)
        } label: {
            HStack {
                StationRow(name: channel.name, favicon: channel.faviconURL, detail: channel.country)
                Spacer()
                if player.isPlaying && player.current?.id == channel.stationID {
                    if player.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct StationRow: View {
    let name: String
    let favicon: String
    let detail: String

    var body: some View {
        HStack {
            StationLogo(url: .stationLogo(favicon))

            VStack(alignment: .leading) {
                Text(name).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct StationLogo: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Image(systemName: "radio").foregroundStyle(.secondary)
        }
        .frame(width: 40, height: 40)
    }
}

extension URL {
    /// Many station logos are plain http, which App Transport Security blocks.
    /// Most of those hosts serve the same file over https.
    static func stationLogo(_ string: String) -> URL? {
        guard var components = URLComponents(string: string), components.host != nil else { return nil }
        if components.scheme == "http" { components.scheme = "https" }
        return components.url
    }
}
