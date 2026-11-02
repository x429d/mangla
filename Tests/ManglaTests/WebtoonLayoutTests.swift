import CoreGraphics
import XCTest

@testable import Mangla

final class WebtoonStripLayoutTests: XCTestCase {
    func testHeightsFollowAspectRatioAndTopsAccumulate() {
        let pages = [
            PageSlot(url: URL(fileURLWithPath: "/tmp/1.png"), pixelSize: CGSize(width: 1000, height: 2000)),
            PageSlot(url: URL(fileURLWithPath: "/tmp/2.png"), pixelSize: CGSize(width: 1000, height: 1000)),
        ]

        let layout = WebtoonStripLayout.make(pages: pages, viewportWidth: 1200)

        XCTAssertEqual(layout.stripWidth, 1000)
        XCTAssertEqual(layout.heights, [2000, 1000])
        XCTAssertEqual(layout.tops, [0, 2000])
        XCTAssertEqual(layout.totalHeight, 3000)
    }

    func testVeryWidePageKeepsMinimumHeight() {
        let pages = [
            PageSlot(url: URL(fileURLWithPath: "/tmp/wide.png"), pixelSize: CGSize(width: 4000, height: 200))
        ]

        let layout = WebtoonStripLayout.make(pages: pages, viewportWidth: 800)

        XCTAssertEqual(layout.stripWidth, 800)
        XCTAssertEqual(layout.heights, [WebtoonStripLayout.minimumPageHeight])
        XCTAssertEqual(layout.totalHeight, WebtoonStripLayout.minimumPageHeight)
    }

    func testStripWidthIsCappedAndViewportIsClamped() {
        let page = PageSlot(url: URL(fileURLWithPath: "/tmp/page.png"), pixelSize: CGSize(width: 800, height: 1200))

        let wide = WebtoonStripLayout.make(pages: [page], viewportWidth: 2000)
        XCTAssertEqual(wide.stripWidth, WebtoonStripLayout.maximumStripWidth)

        let empty = WebtoonStripLayout.make(pages: [page], viewportWidth: 0)
        XCTAssertEqual(empty.stripWidth, 1)
    }

    func testPageIndexFindsThePageUnderAViewportCenter() {
        let pages = [
            PageSlot(url: URL(fileURLWithPath: "/tmp/1.png"), pixelSize: CGSize(width: 1000, height: 2000)),
            PageSlot(url: URL(fileURLWithPath: "/tmp/2.png"), pixelSize: CGSize(width: 1000, height: 1000)),
            PageSlot(url: URL(fileURLWithPath: "/tmp/3.png"), pixelSize: CGSize(width: 1000, height: 500)),
        ]
        let layout = WebtoonStripLayout.make(pages: pages, viewportWidth: 1000)

        XCTAssertEqual(layout.pageIndex(containingY: -10), 0)
        XCTAssertEqual(layout.pageIndex(containingY: 0), 0)
        XCTAssertEqual(layout.pageIndex(containingY: layout.tops[1] - 0.5), 0)
        XCTAssertEqual(layout.pageIndex(containingY: layout.tops[1]), 1)
        XCTAssertEqual(layout.pageIndex(containingY: layout.tops[2]), 2)
        XCTAssertEqual(layout.pageIndex(containingY: layout.totalHeight), 2)
    }

    func testEmptyLayoutHasNoPages() {
        let layout = WebtoonStripLayout.make(pages: [], viewportWidth: 900)

        XCTAssertEqual(layout.stripWidth, 900)
        XCTAssertTrue(layout.heights.isEmpty)
        XCTAssertEqual(layout.totalHeight, 0)
        XCTAssertEqual(layout.pageIndex(containingY: 50), 0)
    }
}

final class PageWindowTests: XCTestCase {
    func testWindowClampsAtTheEdges() throws {
        let start = try XCTUnwrap(PageWindow(center: 0, before: 2, after: 4, pageCount: 10))
        XCTAssertEqual(start.range, 0...4)

        let middle = try XCTUnwrap(PageWindow(center: 5, before: 2, after: 4, pageCount: 10))
        XCTAssertEqual(middle.range, 3...9)

        let end = try XCTUnwrap(PageWindow(center: 9, before: 2, after: 4, pageCount: 10))
        XCTAssertEqual(end.range, 7...9)

        XCTAssertNil(PageWindow(center: 0, before: 2, after: 4, pageCount: 0))
    }

    func testOnlyIndicesThatLeftTheWindowAreReported() throws {
        let previous = try XCTUnwrap(PageWindow(center: 3, before: 2, after: 4, pageCount: 40))
        let shifted = try XCTUnwrap(PageWindow(center: 4, before: 2, after: 4, pageCount: 40))
        XCTAssertEqual(previous.indices(excluding: shifted), [1])

        let jumped = try XCTUnwrap(PageWindow(center: 30, before: 2, after: 4, pageCount: 40))
        XCTAssertEqual(previous.indices(excluding: jumped), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(jumped.indices(excluding: previous), [28, 29, 30, 31, 32, 33, 34])
    }
}
