import SwiftUI
import SwiftData

struct ChannelSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var channels: [Channel]
    @State private var query = ""
    @State private var results: [Station] = []
    @State private var isLoading = false
    @State private var failure: String?

    var body: some View {
        let saved = Set(channels.map(\.stationID))
        NavigationStack {
            List(results) { station in
                let isSaved = saved.contains(station.id)
                Button {
                    context.insert(Channel(station))
                } label: {
                    HStack {
                        StationRow(name: station.name, favicon: station.favicon, detail: detail(station))
                        Spacer()
                        Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundStyle(.tint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSaved)
            }
            .opacity(isLoading ? 0.4 : 1)  // old results stay visible but dimmed while searching
            .animation(.default, value: isLoading)
            .overlay { placeholder }
            .searchable(text: $query, prompt: "Station name")
            .task(id: query) { await search() }
            .navigationTitle("Add Channel")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    @ViewBuilder private var placeholder: some View {
        if query.isEmpty {
            ContentUnavailableView("Search Radio Stations", systemImage: "magnifyingglass")
        } else if isLoading {
            ProgressView()
        } else if let failure {
            ContentUnavailableView("Search Failed", systemImage: "wifi.exclamationmark", description: Text(failure))
        } else if results.isEmpty {
            ContentUnavailableView.search(text: query)
        }
    }

    private func detail(_ station: Station) -> String {
        let format = station.bitrate > 0 ? "\(station.codec) \(station.bitrate) kbps" : station.codec
        return [station.country, format].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Debounced: `.task(id:)` cancels the previous run on every keystroke,
    /// so the API is only asked once typing pauses for half a second.
    private func search() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else {
            results = []
            failure = nil
            isLoading = false
            return
        }
        isLoading = true
        do {
            try await Task.sleep(for: .milliseconds(500))
            let found = try await RadioBrowser.search(name: term)
            guard !Task.isCancelled else { return }
            results = found
            failure = nil
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            failure = error.localizedDescription
        }
        isLoading = false
    }
}
