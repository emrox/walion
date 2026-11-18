import Foundation
import Testing
@testable import Walion

/// Everything that talks to the network, against `StubURLProtocol`. Serialized: they share the stub.
@Suite("Network", .serialized)
struct NetworkTests {
    nonisolated static let apiHost = "api.radio-browser.test"

    /// radio-browser as the stub plays it: a server list, then search and play-count endpoints.
    static func radioBrowser(search: (status: Int, body: String)) -> StubURLProtocol.Handler {
        { url in
            switch url.path() {
            case "/json/servers": (200, Data(#"[{"ip":"1.2.3.4","name":"\#(apiHost)"}]"#.utf8))
            case "/json/stations/search": (search.status, Data(search.body.utf8))
            case let path where path.hasPrefix("/json/url/"): (200, Data(#"{"ok":true}"#.utf8))
            default: (404, Data())
            }
        }
    }

    static let searchJSON = """
    [{"changeuuid":"x","stationuuid":"s-1","name":"ByteFM (192k)","url":"http://byte.example/m3u",
      "url_resolved":"https://byte.example/stream","homepage":"","favicon":"https://byte.example/logo.png",
      "tags":"indie","country":"Germany","countrycode":"DE","codec":"MP3","bitrate":192,"hls":0,"votes":10},
     {"stationuuid":"s-2","name":"Jazz","url_resolved":"http://jazz.example/live","favicon":"",
      "country":"","codec":"AAC","bitrate":0}]
    """

    // MARK: radio-browser

    @Test("Search asks a radio-browser server for working stations, most popular first")
    func searchRequest() async throws {
        StubURLProtocol.respond(with: Self.radioBrowser(search: (200, Self.searchJSON)))
        let results = try await RadioBrowser.search(name: "byte fm")

        #expect(results.map(\.id) == ["s-1", "s-2"])
        #expect(results[0].name == "ByteFM (192k)")
        #expect(results[0].urlResolved == "https://byte.example/stream")
        #expect(results[0].favicon == "https://byte.example/logo.png")
        #expect(results[0].country == "Germany")
        #expect(results[0].codec == "MP3")
        #expect(results[0].bitrate == 192)

        let request = try #require(StubURLProtocol.requests.last)
        #expect(request.host() == Self.apiHost)
        #expect(request.path() == "/json/stations/search")
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: request, resolvingAgainstBaseURL: false)?
            .queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(query == ["name": "byte fm", "limit": "50", "hidebroken": "true", "order": "clickcount", "reverse": "true"])
    }

    @Test("A server error fails the search instead of showing no results")
    func searchServerError() async {
        StubURLProtocol.respond(with: Self.radioBrowser(search: (503, "Service Unavailable")))
        await #expect(throws: URLError.self) { try await RadioBrowser.search(name: "jazz") }
    }

    @Test("A play is reported to radio-browser for the station")
    func countPlay() async throws {
        StubURLProtocol.respond(with: Self.radioBrowser(search: (200, "[]")))
        await RadioBrowser.countPlay(stationID: "s-1")
        let request = try #require(StubURLProtocol.requests.last)
        #expect(request.host() == Self.apiHost)
        #expect(request.path() == "/json/url/s-1")
    }

    // MARK: Logo cache

    nonisolated static let logoURL = "https://logos.test/station.png"

    /// A channel whose logo (on http, as many stations list it) the stub serves.
    func channelWithLogo() -> Channel {
        makeChannel("logo", stream: URL(string: "https://s.example/x")!, favicon: "http://logos.test/station.png")
    }

    func serveLogo(_ logo: Data?) {
        StubURLProtocol.respond { url in
            url.absoluteString == Self.logoURL ? (logo == nil ? (404, Data()) : (200, logo!)) : (404, Data())
        }
    }

    @Test("A new channel's logo is downloaded (over https) and shrunk")
    func firstDownload() async throws {
        serveLogo(try TestImage.png(width: 1000, height: 1000))
        let channel = channelWithLogo()

        await channel.refreshLogoIfNeeded()

        #expect(StubURLProtocol.requests.map(\.absoluteString) == [Self.logoURL])
        let logo = try #require(channel.logoData)
        #expect(try TestImage.info(logo).width == 512)
        #expect(channel.logoCheckedAt != nil)
    }

    @Test("A logo checked less than a week ago isn't downloaded again", arguments: [0.0, 1, 6.9])
    func noRefreshWithinAWeek(daysAgo: Double) async throws {
        serveLogo(try TestImage.png(width: 64, height: 64))
        let channel = channelWithLogo()
        channel.logoData = Data([1])
        channel.logoCheckedAt = .now.addingTimeInterval(-daysAgo * 86_400)

        await channel.refreshLogoIfNeeded()

        #expect(StubURLProtocol.requests.isEmpty)
        #expect(channel.logoData == Data([1]))
    }

    @Test("A logo older than a week is refreshed")
    func refreshAfterAWeek() async throws {
        serveLogo(try TestImage.png(width: 64, height: 64))
        let channel = channelWithLogo()
        channel.logoData = Data([1])
        channel.logoCheckedAt = .now.addingTimeInterval(-8 * 86_400)

        await channel.refreshLogoIfNeeded()

        #expect(StubURLProtocol.requests.count == 1)
        #expect(try TestImage.info(#require(channel.logoData)).width == 64)
    }

    @Test("A failed refresh keeps the old logo and waits another week")
    func failedRefreshKeepsLogo() async throws {
        serveLogo(nil)  // 404
        let channel = channelWithLogo()
        channel.logoData = Data([1])
        channel.logoCheckedAt = .now.addingTimeInterval(-8 * 86_400)

        await channel.refreshLogoIfNeeded()

        #expect(StubURLProtocol.requests.count == 1)
        #expect(channel.logoData == Data([1]))
        #expect(try #require(channel.logoCheckedAt).timeIntervalSinceNow > -60)
    }

    @Test("A downloaded page that isn't an image keeps the old logo")
    func nonImageKeepsLogo() async throws {
        serveLogo(Data("<html>moved</html>".utf8))
        let channel = channelWithLogo()
        channel.logoData = Data([1])
        channel.logoCheckedAt = .now.addingTimeInterval(-8 * 86_400)

        await channel.refreshLogoIfNeeded()

        #expect(channel.logoData == Data([1]))
    }

    @Test("Without any logo, the next try is after a day", arguments: [(2.0, false), (23.0, false), (25.0, true)])
    func missingLogoRetriesDaily(hoursAgo: Double, expectRequest: Bool) async throws {
        serveLogo(nil)
        let channel = channelWithLogo()
        channel.logoCheckedAt = .now.addingTimeInterval(-hoursAgo * 3600)

        await channel.refreshLogoIfNeeded()

        #expect(StubURLProtocol.requests.count == (expectRequest ? 1 : 0))
    }

    @Test("A station without a logo URL never makes a request")
    func noLogoURL() async {
        serveLogo(nil)
        let channel = makeChannel("none", stream: URL(string: "https://s.example/x")!, favicon: "")

        await channel.refreshLogoIfNeeded()

        #expect(StubURLProtocol.requests.isEmpty)
    }
}
