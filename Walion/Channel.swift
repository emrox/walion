import Foundation
import SwiftData

/// A radio station the user saved to their channel list.
@Model
final class Channel {
    @Attribute(.unique) var stationID: String
    var name: String
    var streamURL: String
    var faviconURL: String
    var country: String
    var addedAt = Date.now
    /// When this channel last started playing, for "Recently Played".
    var lastPlayedAt: Date?

    init(_ station: Station) {
        stationID = station.id
        name = station.name
        streamURL = station.urlResolved
        faviconURL = station.favicon
        country = station.country
    }
}
