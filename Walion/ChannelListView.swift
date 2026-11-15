import SwiftUI
import SwiftData

struct ChannelListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Channel.addedAt) private var channels: [Channel]
    @State private var isSearching = false

    var body: some View {
        List {
            ForEach(channels) { channel in
                StationRow(name: channel.name, favicon: channel.faviconURL, detail: channel.country)
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
    }
}

struct StationRow: View {
    let name: String
    let favicon: String
    let detail: String

    var body: some View {
        HStack {
            AsyncImage(url: URL(string: favicon)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "radio").foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading) {
                Text(name).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
