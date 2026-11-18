import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Walion

@Suite("Station logos")
struct StationLogoTests {
    @Test("http logo URLs are upgraded to https, since App Transport Security blocks http")
    func upgradesHTTP() {
        #expect(URL.stationLogo("http://radio.example/logo.png")?.absoluteString == "https://radio.example/logo.png")
        #expect(URL.stationLogo("https://radio.example/logo.png?v=2")?.absoluteString == "https://radio.example/logo.png?v=2")
    }

    @Test("Missing or unusable logo URLs give no URL", arguments: ["", "logo.png", "not a url"])
    func rejectsUnusable(_ string: String) {
        #expect(URL.stationLogo(string) == nil)
    }

    @Test("Large logos are shrunk to 512 px, keeping the aspect ratio")
    func shrinksLargeLogos() throws {
        let thumbnail = try #require(LogoImage.thumbnail(from: TestImage.png(width: 1024, height: 512)))
        let info = try TestImage.info(thumbnail)
        #expect(info.width == 512)
        #expect(info.height == 256)
    }

    @Test("Small logos keep their size")
    func keepsSmallLogos() throws {
        let thumbnail = try #require(LogoImage.thumbnail(from: TestImage.png(width: 96, height: 96)))
        let info = try TestImage.info(thumbnail)
        #expect(info.width == 96)
    }

    @Test("Opaque logos are stored as JPEG, transparent ones as PNG")
    func picksFormat() throws {
        let opaque = try #require(LogoImage.thumbnail(from: TestImage.png(width: 200, height: 200, opaque: true)))
        let transparent = try #require(LogoImage.thumbnail(from: TestImage.png(width: 200, height: 200, opaque: false)))
        #expect(try TestImage.info(opaque).type == .jpeg)
        #expect(try TestImage.info(transparent).type == .png)
    }

    @Test("From a multi-size .ico, the largest size is used")
    func picksLargestIcoFrame() throws {
        let ico = try TestImage.encode([
            TestImage.cgImage(width: 16, height: 16, opaque: false),
            TestImage.cgImage(width: 64, height: 64, opaque: false),
            TestImage.cgImage(width: 32, height: 32, opaque: false),
        ], as: .ico)
        let thumbnail = try #require(LogoImage.thumbnail(from: ico))
        #expect(try TestImage.info(thumbnail).width == 64)
    }

    @Test("Data that isn't an image gives no logo")
    func rejectsNonImages() {
        #expect(LogoImage.thumbnail(from: Data("<html>404</html>".utf8)) == nil)
        #expect(LogoImage.image(Data()) == nil)
    }

    @Test("A cached logo can be drawn")
    func drawsCachedLogo() throws {
        let thumbnail = try #require(LogoImage.thumbnail(from: TestImage.png(width: 64, height: 64)))
        #expect(LogoImage.image(thumbnail) != nil)
    }
}
