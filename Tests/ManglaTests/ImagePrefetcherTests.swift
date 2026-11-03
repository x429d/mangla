import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import Mangla

final class ImagePrefetcherTests: XCTestCase {
    func testReleaseMemoryDropsCachedPages() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManglaPrefetcher-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(to: url)

        let source = PageSource.imageFile(url)
        let prefetcher = ImagePrefetcher()
        let image = try await prefetcher.image(for: source)
        XCTAssertEqual(image.width, 4)
        let cached = await prefetcher.cachedImage(for: source)
        XCTAssertNotNil(cached)

        await prefetcher.releaseMemory()

        let released = await prefetcher.cachedImage(for: source)
        XCTAssertNil(released)
    }

    func testTrimMemoryDropsCachedPages() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManglaPrefetcherTrim-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(to: url)

        let source = PageSource.imageFile(url)
        let prefetcher = ImagePrefetcher()
        _ = try await prefetcher.image(for: source)
        let cached = await prefetcher.cachedImage(for: source)
        XCTAssertNotNil(cached)

        await prefetcher.trimMemory()

        let trimmed = await prefetcher.cachedImage(for: source)
        XCTAssertNil(trimmed)

        // The page must still decode after a cache trim; only the retained
        // copy goes away.
        let reloaded = try await prefetcher.image(for: source)
        XCTAssertEqual(reloaded.width, 4)
        await prefetcher.releaseMemory()
    }

    private func writePNG(to url: URL) throws {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 4,
                height: 4,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
