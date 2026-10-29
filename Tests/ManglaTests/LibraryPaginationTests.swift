import XCTest

@testable import Mangla

final class LibraryPaginationTests: XCTestCase {
    func testEmptyLibraryStillHasOnePage() {
        XCTAssertEqual(LibraryPagination.pageCount(total: 0), 1)
        XCTAssertEqual(LibraryPagination.range(total: 0, page: 0), 0..<0)
        XCTAssertEqual(LibraryPagination.rangeLabel(total: 0, page: 0), "0 из 0")
    }

    func testPageCountAtBoundaries() {
        XCTAssertEqual(LibraryPagination.pageCount(total: 30), 1)
        XCTAssertEqual(LibraryPagination.pageCount(total: 31), 2)
        XCTAssertEqual(LibraryPagination.pageCount(total: 60), 2)
        XCTAssertEqual(LibraryPagination.pageCount(total: 61), 3)
    }

    func testRangesAndClamping() {
        XCTAssertEqual(LibraryPagination.range(total: 503, page: 0), 0..<30)
        XCTAssertEqual(LibraryPagination.range(total: 503, page: 1), 30..<60)
        XCTAssertEqual(LibraryPagination.range(total: 503, page: 16), 480..<503)
        XCTAssertEqual(LibraryPagination.range(total: 61, page: 99), 60..<61)
        XCTAssertEqual(LibraryPagination.clampedPage(-5, total: 61), 0)
        XCTAssertEqual(LibraryPagination.clampedPage(99, total: 61), 2)
    }

    func testRangeLabels() {
        XCTAssertEqual(LibraryPagination.rangeLabel(total: 503, page: 0), "1–30 из 503")
        XCTAssertEqual(LibraryPagination.rangeLabel(total: 503, page: 1), "31–60 из 503")
        XCTAssertEqual(LibraryPagination.rangeLabel(total: 503, page: 16), "481–503 из 503")
        XCTAssertEqual(LibraryPagination.rangeLabel(total: 12, page: 0), "1–12 из 12")
    }
}
