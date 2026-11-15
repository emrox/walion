import SwiftUI
import SwiftData

@main
struct WalionApp: App {
    @State private var player = RadioPlayer()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    NavigationLink {
                        ChannelListView()
                    } label: {
                        Label("Radio Channels", systemImage: "radio")
                    }
                }
                .navigationTitle("Walion")
            }
            .safeAreaInset(edge: .bottom) { NowPlayingBar() }
            .environment(player)
        }
        .modelContainer(for: Channel.self)
    }
}
