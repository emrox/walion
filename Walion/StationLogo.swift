import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// A station logo: the cached copy when there is one, otherwise loaded from `url`.
struct StationLogo: View {
    var data: Data?
    var url: URL?

    var body: some View {
        Group {
            if let image = data.flatMap(LogoImage.image) {
                image.resizable().scaledToFit()
            } else {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: "radio").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 40, height: 40)
    }
}

extension URL {
    /// Many station logos are plain http, which App Transport Security blocks.
    /// Most of those hosts serve the same file over https.
    nonisolated static func stationLogo(_ string: String) -> URL? {
        guard var components = URLComponents(string: string), components.host != nil else { return nil }
        if components.scheme == "http" { components.scheme = "https" }
        return components.url
    }
}

/// Logo files as downloaded can be anything: 16 px favicons, multi-size .ico files,
/// 1500 px photos. The cache keeps one image of at most 512 px: sharp enough for the lock
/// screen, small and quick to draw in every row. PNG when it has transparency, else JPEG.
nonisolated enum LogoImage {
    static func thumbnail(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        // .ico files hold several sizes; take the largest.
        let largest = (0..<CGImageSourceGetCount(source)).max { pixelWidth(source, $0) < pixelWidth(source, $1) } ?? 0
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, largest, options) else { return nil }
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let output = NSMutableData()
        let type = opaque ? UTType.jpeg : UTType.png
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    static func image(_ data: Data) -> Image? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Image(decorative: cgImage, scale: 1)
    }

    private static func pixelWidth(_ source: CGImageSource, _ index: Int) -> Int {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        return properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
    }
}
