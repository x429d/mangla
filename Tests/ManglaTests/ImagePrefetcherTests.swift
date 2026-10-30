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

        let prefetcher = ImagePrefetcher()
        let image = try await prefetcher.image(for: url)
        XCTAssertEqual(image.width, 4)
        let cached = await prefetcher.cachedImage(for: url)
        XCTAssertNotNil(cached)

        await prefetcher.releaseMemory()

        let released = await prefetcher.cachedImage(for: url)
        XCTAssertNil(released)
    }

    private func writePNG(to url: URL) throws {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 4,
            height: 4,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
