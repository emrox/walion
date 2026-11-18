import AVFoundation
import MediaPlayer
import SwiftUI

/// Plays one live radio stream at a time. Shared app-wide via the environment.
///
/// Every (re)start gets a fresh muted stream. The stream already playing keeps
/// going until the new one actually produces audio, then they swap. If the new one
/// fails, the old one just keeps playing.
@Observable
final class RadioPlayer {
    struct Station: Equatable {
        let id: String
        let name: String
        let url: URL
        let logo: URL?

        init?(_ channel: Channel) {
            guard let url = URL(string: channel.streamURL) else { return nil }
            id = channel.stationID
            name = channel.name
            self.url = url
            logo = .stationLogo(channel.faviconURL)
        }
    }

    /// The channel list, in order, for next/previous.
    @ObservationIgnored var channels: [Station] = []

    private(set) var current: Station?
    /// The station you actually hear, once its audio has started.
    private(set) var playing: Station?
    private(set) var isPlaying = false
    /// Connecting, switching or rebuffering.
    private(set) var isLoading = false
    private(set) var error: String?
    /// What the station says is on air right now: usually "Artist - Title", sometimes a show name.
    private(set) var streamTitle: String?
    /// When the sleep timer will stop playback.
    private(set) var sleepAt: Date?

    /// The stream you hear.
    @ObservationIgnored private var player: Stream?
    /// The stream being loaded, muted until it plays.
    @ObservationIgnored private var next: Stream?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    /// When the system last paused us (see `update()`), and whether to resume after an interruption.
    @ObservationIgnored private var systemStoppedAt: Date?
    @ObservationIgnored private var resumeAfterInterruption = false
    /// Lock screen image for the station whose logo is `url`.
    @ObservationIgnored private var artwork: (url: URL, image: MPMediaItemArtwork)?

    init() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        // Phone calls, Siri, alarms: iOS says when they end and whether we may continue.
        _ = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let began = type == AVAudioSession.InterruptionType.began.rawValue
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
            MainActor.assumeIsolated { self?.handleInterruption(began: began, shouldResume: shouldResume) }
        }
        #endif
        // Lock screen, Control Center, Dynamic Island, macOS Now Playing and media keys.
        // Live radio has no pause: "pause" means stop.
        let commands = MPRemoteCommandCenter.shared()
        let handlers: [(MPRemoteCommand, @Sendable @MainActor (RadioPlayer) -> Void)] = [
            (commands.playCommand, { $0.resume() }),
            (commands.pauseCommand, { $0.stop() }),
            (commands.stopCommand, { $0.stop() }),
            (commands.togglePlayPauseCommand, { $0.toggle() }),
            (commands.nextTrackCommand, { $0.skip(1) }),
            (commands.previousTrackCommand, { $0.skip(-1) }),
        ]
        for (command, action) in handlers {
            command.addTarget { @Sendable [weak self] _ in
                DispatchQueue.main.async { if let self { action(self) } }
                return .success
            }
        }
    }

    func play(_ channel: Channel) {
        guard let station = Station(channel) else {
            error = "Invalid stream URL"
            return
        }
        play(station)
    }

    func play(_ station: Station) {
        current = station
        resume()
        loadArtwork(station.logo)
    }

    /// Next (1) or previous (-1) channel in the list, wrapping around.
    func skip(_ offset: Int) {
        guard !channels.isEmpty else { return }
        let index = channels.firstIndex { $0.id == current?.id }
            .map { ($0 + offset + channels.count) % channels.count } ?? 0
        play(channels[index])
    }

    /// Live radio: always reconnect instead of un-pausing a stale buffer.
    func resume() {
        guard let current else { return }
        resumeAfterInterruption = false
        next?.stop()
        next = Stream(current) { [weak self] in self?.update() }
        isPlaying = true
        error = nil
        update()
    }

    func toggle() {
        isPlaying ? stop() : resume()
    }

    /// Stop playback after `duration`; nil turns the timer off. Stopping by hand also turns it off.
    func setSleepTimer(_ duration: Duration?) {
        sleepTask?.cancel()
        sleepTask = nil
        sleepAt = nil
        guard let duration else { return }
        sleepAt = .now.addingTimeInterval(Double(duration.components.seconds))
        sleepTask = Task { [weak self] in
            // Continuous clock: keeps counting while the device sleeps.
            // The last 10 seconds fade the volume down instead of cutting off.
            let fade = min(duration, .seconds(10))
            let steps = 50
            do {
                try await Task.sleep(for: duration - fade)
                for step in 1...steps {
                    try await Task.sleep(for: fade / steps)
                    self?.player?.player.volume = Float(steps - step) / Float(steps)
                }
            } catch {
                self?.player?.player.volume = 1  // timer changed or turned off mid-fade
                return
            }
            self?.stop()
        }
    }

    func stop() {
        setSleepTimer(nil)
        next?.stop()
        next = nil
        player?.stop()
        player = nil
        playing = nil
        isPlaying = false
        isLoading = false
        streamTitle = nil
        publishNowPlaying()
    }

    /// Resume after an interruption only if we were playing when it began. The player may
    /// already have paused (and we stopped) a moment before iOS tells us it began, hence the
    /// 2-second window. Older system stops, like unplugged headphones, don't count.
    func handleInterruption(began: Bool, shouldResume: Bool) {
        if began {
            let justStopped = systemStoppedAt.map { Date.now.timeIntervalSince($0) < 2 } ?? false
            resumeAfterInterruption = isPlaying || justStopped
        } else if shouldResume && resumeAfterInterruption {
            resume()
        }
    }

    /// Runs on every status or metadata change of either stream.
    private func update() {
        if let next, next.player.currentItem?.status == .failed {
            let reason = next.player.currentItem?.error?.localizedDescription ?? "Playback failed"
            if player == nil {
                stop()
                error = reason
            } else {
                error = "Couldn't play \(next.station.name): \(reason)"
                next.stop()
                self.next = nil
                current = player?.station
            }
        }
        if player?.player.currentItem?.status == .failed {
            let reason = player?.player.currentItem?.error?.localizedDescription ?? "Playback failed"
            stop()
            error = reason
        }
        if let loaded = next, loaded.player.timeControlStatus == .playing {
            player?.stop()
            loaded.player.isMuted = false
            player = loaded
            playing = loaded.station
            next = nil
        }
        // We never pause the audible stream ourselves, so the system did: another app
        // took the audio, a phone call, headphones unplugged, or the station ended the stream.
        if isPlaying, player?.player.timeControlStatus == .paused {
            stop()
            systemStoppedAt = .now
        }
        isLoading = next != nil || player?.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        // Some stations just repeat their name; that adds nothing.
        if let player, player.station == current, let title = player.title,
           !player.station.name.localizedCaseInsensitiveContains(title) {
            streamTitle = title
        } else {
            streamTitle = nil
        }
        publishNowPlaying()
    }

    /// What the system shows on the lock screen, in Control Center and the Dynamic Island.
    private func publishNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = current.map { station in
            var info: [String: Any] = [
                MPMediaItemPropertyTitle: streamTitle ?? station.name,
                MPMediaItemPropertyArtist: streamTitle == nil ? "" : station.name,
                MPNowPlayingInfoPropertyIsLiveStream: true,
                MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            ]
            if let artwork, artwork.url == station.logo {
                info[MPMediaItemPropertyArtwork] = artwork.image
            }
            return info
        }
        center.playbackState = isPlaying ? .playing : .paused
    }

    private func loadArtwork(_ url: URL?) {
        guard let url, artwork?.url != url else { return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = Self.artwork(from: data) else { return }
            artwork = (url, image)
            publishNowPlaying()
        }
    }

    /// Nonisolated: the system asks for the image on a background thread.
    nonisolated private static func artwork(from data: Data) -> MPMediaItemArtwork? {
        #if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        #else
        guard let image = UIImage(data: data) else { return nil }
        #endif
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}

/// One connection to a station: its player and the latest title the stream announced.
private final class Stream {
    let station: RadioPlayer.Station
    let player: AVPlayer
    private(set) var title: String?
    private let onChange: () -> Void
    // KVO tokens. Not `publisher(for:).values`: that only ever delivers the initial value here.
    private var observations: [NSKeyValueObservation] = []
    private var metadataReader: MetadataReader?

    init(_ station: RadioPlayer.Station, onChange: @escaping () -> Void) {
        self.station = station
        self.onChange = onChange
        let item = AVPlayerItem(url: station.url)
        player = AVPlayer(playerItem: item)

        let changed: @Sendable (Any, Any) -> Void = { [weak self] _, _ in
            DispatchQueue.main.async { self?.onChange() }
        }
        observations = [
            player.observe(\.timeControlStatus, changeHandler: changed),
            item.observe(\.status, changeHandler: changed),
        ]
        metadataReader = MetadataReader(item) { [weak self] title in
            self?.title = title
            self?.onChange()
        }

        player.isMuted = true
        player.play()
    }

    func stop() {
        player.pause()
    }
}

/// Reads "now playing" text from a stream: Icecast's StreamTitle or HLS ID3 tags.
private final class MetadataReader: NSObject, AVPlayerItemMetadataOutputPushDelegate, Sendable {
    private let onTitle: @Sendable @MainActor (String?) -> Void

    init(_ item: AVPlayerItem, onTitle: @escaping @Sendable @MainActor (String?) -> Void) {
        self.onTitle = onTitle
        super.init()
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(self, queue: .main)
        item.add(output)
    }

    nonisolated func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                                    didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                                    from track: AVPlayerItemTrack?) {
        // AVMetadataItem is immutable (only its AVMutableMetadataItem subclass isn't), just not marked Sendable.
        nonisolated(unsafe) let items = groups.flatMap(\.items)
        guard items.contains(where: { $0.commonKey == .commonKeyTitle || $0.commonKey == .commonKeyArtist })
        else { return }  // e.g. Icecast's empty "icy/json" item
        Task { [onTitle] in
            let parts = [await Self.text(.commonKeyArtist, in: items), await Self.text(.commonKeyTitle, in: items)]
            let text = parts.compactMap { $0 }.joined(separator: " - ")
            await onTitle(text.isEmpty ? nil : text)
        }
    }

    nonisolated private static func text(_ key: AVMetadataKey, in items: [AVMetadataItem]) async -> String? {
        guard let item = items.first(where: { $0.commonKey == key }),
              let value = try? await item.load(.stringValue) else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

struct NowPlayingBar: View {
    @Environment(RadioPlayer.self) private var player

    var body: some View {
        if let station = player.current {
            HStack {
                StationLogo(url: station.logo)
                VStack(alignment: .leading) {
                    Text(station.name).lineLimit(1)
                    Text(player.error ?? (player.isLoading ? "Loading…" : player.isPlaying ? player.streamTitle ?? "Live" : "Stopped"))
                        .font(.caption)
                        .foregroundStyle(player.error == nil ? Color.secondary : Color.red)
                        .lineLimit(1)
                }
                Spacer()
                if player.isLoading {
                    ProgressView().controlSize(.small)
                }
                if player.isPlaying {
                    SleepTimerMenu()
                }
                Button(player.isPlaying ? "Stop" : "Play",
                       systemImage: player.isPlaying ? "stop.fill" : "play.fill") {
                    player.toggle()
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .buttonStyle(.plain)
            }
            .padding()
            .background(.bar)
        }
    }
}
