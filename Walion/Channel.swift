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
    /// Cached station logo (PNG or JPEG, at most 512 px), see `refreshLogoIfNeeded()`.
    @Attribute(.externalStorage) var logoData: Data?
    var logoCheckedAt: Date?

    init(_ result: SearchResult, position: Int = 0) {
        self.position = position
        stationID = result.id
        name = result.name
        streamURL = result.urlResolved
        faviconURL = result.favicon
        country = result.country
    }
}

extension Channel {
    /// Downloads the logo when there's none yet, and refreshes it once a week. A failed
    /// refresh keeps the old logo. Without any logo, retries after a day.
    /// Main actor: it changes the model, which the UI's context owns.
    @MainActor func refreshLogoIfNeeded() async {
        let maxAge: TimeInterval = logoData == nil ? 24 * 3600 : 7 * 24 * 3600
        if let logoCheckedAt, Date.now.timeIntervalSince(logoCheckedAt) < maxAge { return }
        guard let url = URL.stationLogo(faviconURL) else { return }
        logoCheckedAt = .now  // first, so a row shown twice doesn't download twice
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let thumbnail = LogoImage.thumbnail(from: data) else { return }
        logoData = thumbnail
    }
}
