import SwiftUI
import SwiftData

@main
struct WalionApp: App {
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
        }
        .modelContainer(for: Channel.self)
    }
}
