import SwiftUI
import SwiftData

@main
struct WalionApp: App {
    @State private var player = RadioPlayer()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(player)
        }
        .modelContainer(for: Channel.self)
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(RadioPlayer.self) private var player
    @Query(filter: #Predicate<Channel> { $0.lastPlayedAt != nil },
           sort: [SortDescriptor(\Channel.lastPlayedAt, order: .reverse)])
    private var recentlyPlayed: [Channel]

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ChannelListView()
                } label: {
                    Label("Radio Channels", systemImage: "radio")
                }
                if !recentlyPlayed.isEmpty {
                    Section("Recently Played") {
                        ForEach(recentlyPlayed.prefix(3)) { channel in
                            ChannelRow(channel: channel)
                        }
                    }
                }
            }
            .navigationTitle("Walion")
        }
        .safeAreaInset(edge: .bottom) { NowPlayingBar() }
        // Lives here, not in a list view, so lock-screen next/previous counts too.
        .onChange(of: player.playing) {
            guard let id = player.playing?.id else { return }
            let match = try? context.fetch(FetchDescriptor<Channel>(predicate: #Predicate { $0.stationID == id }))
            match?.first?.lastPlayedAt = .now
            try? context.save()  // don't wait for autosave; the app may be killed while playing
        }
    }
}
