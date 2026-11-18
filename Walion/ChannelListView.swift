import SwiftUI
import SwiftData

struct ChannelListView: View {
    @Environment(\.modelContext) private var context
    @Environment(RadioPlayer.self) private var player
    @Query(sort: [SortDescriptor(\Channel.position), SortDescriptor(\Channel.addedAt)])
    private var channels: [Channel]
    @State private var isSearching = false

    var body: some View {
        List {
            ForEach(channels) { channel in
                ChannelRow(channel: channel)
                    #if os(macOS)
                    // iOS: swipe to delete instead; a context menu would take the long press
                    // that starts dragging a row.
                    .contextMenu {
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            context.delete(channel)
                        }
                    }
                    #endif
            }
            .onDelete { offsets in
                offsets.map { channels[$0] }.forEach(context.delete)
            }
            .onMove { from, to in
                Self.move(channels, from: from, to: to)
                try? context.save()
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

extension ChannelListView {
    /// A drag in the list: renumbers `channels` (given in list order) so the moved rows land at `destination`.
    static func move(_ channels: [Channel], from source: IndexSet, to destination: Int) {
        var reordered = channels
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, channel) in reordered.enumerated() {
            channel.position = index
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
                StationRow(name: channel.name, favicon: channel.faviconURL, logo: channel.logoData, detail: channel.country)
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
        // Not `.task`: scrolling away must not cancel a download that's already under way.
        .onAppear { Task { await channel.refreshLogoIfNeeded() } }
    }
}

struct StationRow: View {
    let name: String
    let favicon: String
    var logo: Data? = nil
    let detail: String

    var body: some View {
        HStack {
            StationLogo(data: logo, url: .stationLogo(favicon))

            VStack(alignment: .leading) {
                Text(name).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
