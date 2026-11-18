import Foundation
import SwiftData
import Testing
@testable import Walion

@Suite("Channels")
struct ChannelTests {
    @Test("A saved channel takes its details from the search result")
    func createdFromSearchResult() {
        let result = SearchResult(stationuuid: "id-1", name: "ByteFM", urlResolved: "https://stream.example/byte",
                                  favicon: "http://byte.example/logo.png", country: "Germany", codec: "MP3", bitrate: 192)
        let channel = Channel(result, position: 4)
        #expect(channel.stationID == "id-1")
        #expect(channel.name == "ByteFM")
        #expect(channel.streamURL == "https://stream.example/byte")
        #expect(channel.faviconURL == "http://byte.example/logo.png")
        #expect(channel.country == "Germany")
        #expect(channel.position == 4)
        #expect(channel.lastPlayedAt == nil)
        #expect(channel.logoData == nil)
    }

    @Test("New channels go to the end of the list", arguments: [
        ([], 0),
        ([0, 0, 0], 1),  // channels saved before the list was sortable
        ([0, 3, 1], 4),
    ])
    func nextPosition(existing: [Int], expected: Int) {
        let channels = existing.map { Channel(sampleResult, position: $0) }
        #expect(Channel.nextPosition(after: channels) == expected)
    }

    @Test("Dragging a row renumbers the list, and the new order is what the list shows")
    func moveRow() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let names = ["A", "B", "C", "D"]
        for name in names { context.insert(makeChannel(name, stream: URL(string: "https://s.example/\(name)")!)) }
        let listOrder = FetchDescriptor<Channel>(sortBy: [SortDescriptor(\.position), SortDescriptor(\.addedAt)])
        let channels = try context.fetch(listOrder)
        try #require(channels.map(\.stationID) == names)

        ChannelListView.move(channels, from: [3], to: 0)  // D to the top
        #expect(try context.fetch(listOrder).map(\.stationID) == ["D", "A", "B", "C"])

        ChannelListView.move(try context.fetch(listOrder), from: [0], to: 4)  // and back to the end
        #expect(try context.fetch(listOrder).map(\.stationID) == names)
    }

    @Test("Playing a channel marks it for Recently Played")
    func markPlayed() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let a = makeChannel("A", stream: URL(string: "https://s.example/a")!)
        let b = makeChannel("B", stream: URL(string: "https://s.example/b")!)
        context.insert(a)
        context.insert(b)

        Channel.markPlayed(stationID: "B", in: context)
        #expect(b.lastPlayedAt != nil)
        #expect(a.lastPlayedAt == nil)
        #expect(!context.hasChanges)  // saved right away

        Channel.markPlayed(stationID: "unknown", in: context)  // a removed channel: nothing happens
        #expect(a.lastPlayedAt == nil)
    }

    @Test("The player's station is built from the channel, logo URL upgraded and cached logo included")
    func playerStation() throws {
        let channel = makeChannel("A", stream: URL(string: "https://s.example/a")!, favicon: "http://logo.example/a.png")
        channel.logoData = Data([1, 2, 3])
        let station = try #require(RadioPlayer.Station(channel))
        #expect(station.id == "A")
        #expect(station.url.absoluteString == "https://s.example/a")
        #expect(station.logo?.absoluteString == "https://logo.example/a.png")
        #expect(station.logoData == Data([1, 2, 3]))

        channel.streamURL = ""
        #expect(RadioPlayer.Station(channel) == nil)
    }

    private var sampleResult: SearchResult {
        SearchResult(stationuuid: UUID().uuidString, name: "X", urlResolved: "https://s.example/x",
                     favicon: "", country: "", codec: "", bitrate: 0)
    }
}
