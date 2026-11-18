import AVFoundation
import Foundation
import ImageIO
import SwiftData
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import Walion

/// Waits until `condition` holds, checking every 50 ms. Records a test failure on timeout.
func waitUntil(
    _ description: String, timeout: Duration = .seconds(10),
    sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool
) async {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out waiting until \(description)", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(50))
    }
}

/// A saved channel as the app creates it from a search result.
func makeChannel(_ id: String, stream: URL, favicon: String = "") -> Channel {
    Channel(SearchResult(stationuuid: id, name: id, urlResolved: stream.absoluteString,
                         favicon: favicon, country: "Germany", codec: "MP3", bitrate: 128))
}

func makeInMemoryContainer() throws -> ModelContainer {
    try ModelContainer(for: Channel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
}

/// Silent audio files the player plays like a stream: no network, no sound.
enum TestAudio {
    static func silence(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "walion-test-\(UUID().uuidString).caf")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        buffer.floatChannelData?[0].update(repeating: 0, count: Int(frames))
        do {  // the file is closed when it goes out of scope
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        return url
    }

    /// Fails to load, like a dead stream.
    static let missing = URL(fileURLWithPath: "/nonexistent/walion-test.caf")
}

/// Generated images in any size, with or without transparency.
enum TestImage {
    static func cgImage(width: Int, height: Int, opaque: Bool) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.6, blue: 0.5, alpha: opaque ? 1 : 0.5)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    static func encode(_ images: [CGImage], as type: UTType) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, images.count, nil))
        images.forEach { CGImageDestinationAddImage(destination, $0, nil) }
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func png(width: Int, height: Int, opaque: Bool = true) throws -> Data {
        try encode([cgImage(width: width, height: height, opaque: opaque)], as: .png)
    }

    /// Pixel size and file type of encoded image data.
    static func info(_ data: Data) throws -> (width: Int, height: Int, type: UTType?) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
                properties[kCGImagePropertyPixelHeight] as? Int ?? 0,
                CGImageSourceGetType(source).flatMap { UTType($0 as String) })
    }
}

/// Answers every URLSession request in this process from `handler`, and records it.
nonisolated final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URL) -> (status: Int, body: Data)
    private struct State {
        var handler: Handler = { _ in (404, Data()) }
        var requests: [URL] = []
    }
    private static let state = Mutex(State())
    private static let registered: Void = { URLProtocol.registerClass(StubURLProtocol.self) }()

    /// Starts intercepting (once per process) and replaces the handler and request log.
    static func respond(with handler: @escaping Handler) {
        _ = registered
        state.withLock { $0 = State(handler: handler) }
    }

    static var requests: [URL] { state.withLock { $0.requests } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let (status, body) = Self.state.withLock { state in
            state.requests.append(url)
            return state.handler(url)
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
