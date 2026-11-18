import Foundation

/// A station found by a radio-browser.info search. Saved as a `Channel`; played as a `RadioPlayer.Station`.
nonisolated struct SearchResult: Decodable, Identifiable, Sendable {
    let stationuuid: String
    let name: String
    let urlResolved: String
    let favicon: String
    let country: String
    let codec: String
    let bitrate: Int

    var id: String { stationuuid }
}

/// Client for https://api.radio-browser.info
enum RadioBrowser {
    private struct Server: Decodable { let name: String }

    /// radio-browser asks clients to pick a random mirror from the server list instead of hardcoding one.
    private static let server = Task<URL, Never> {
        let list = URL(string: "https://all.api.radio-browser.info/json/servers")!
        if let (data, _) = try? await URLSession.shared.data(from: list),
           let name = (try? JSONDecoder().decode([Server].self, from: data))?.randomElement()?.name {
            return URL(string: "https://\(name)")!
        }
        return URL(string: "https://de1.api.radio-browser.info")!
    }

    static func search(name: String) async throws -> [SearchResult] {
        let url = await server.value
            .appending(path: "json/stations/search")
            .appending(queryItems: [
                URLQueryItem(name: "name", value: name),
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "hidebroken", value: "true"),
                URLQueryItem(name: "order", value: "clickcount"),
                URLQueryItem(name: "reverse", value: "true"),
            ])
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([SearchResult].self, from: data)
    }

    /// Tells radio-browser a station was played, as its API asks; this feeds the popularity
    /// ranking that search results are sorted by. Counted at most once per station per day.
    /// Best effort: failures don't matter to the user.
    static func countPlay(stationID: String) async {
        let url = await server.value.appending(path: "json/url/\(stationID)")
        _ = try? await URLSession.shared.data(from: url)
    }
}
