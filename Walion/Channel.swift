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
    /// Place in the channel list; the user can drag to reorder. Ties sort by `addedAt`.
    var position = 0

    init(_ result: SearchResult, position: Int = 0) {
        self.position = position
        stationID = result.id
        name = result.name
        streamURL = result.urlResolved
        faviconURL = result.favicon
        country = result.country
    }
}
