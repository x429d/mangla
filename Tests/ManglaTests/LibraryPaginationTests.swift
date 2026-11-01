import XCTest

@testable import Mangla

// Russian strings here are intentional fixtures for the shipped localization.
final class LibraryPaginationTests: XCTestCase {
    private let english = Localization(language: .english)
    private let russian = Localization(language: .russian)

    func testEmptyLibraryStillHasOnePage() {
        XCTAssertEqual(LibraryPagination.pageCount(total: 0), 1)
        XCTAssertEqual(LibraryPagination.range(total: 0, page: 0), 0..<0)
        XCTAssertEqual(LibraryPagination.rangeLabel(total: 0, page: 0, localization: english), "0 of 0")
        XCTAssertEqual(LibraryPagination.rangeLabel(total: 0, page: 0, localization: russian), "0 из 0")
    }

    func testDefaultPageSizeIsThirtyTwo() {
        XCTAssertEqual(LibraryPagination.defaultPageSize, 32)
    }

    func testPageCountAtBoundaries() {
        XCTAssertEqual(LibraryPagination.pageCount(total: 32), 1)
        XCTAssertEqual(LibraryPagination.pageCount(total: 33), 2)
        XCTAssertEqual(LibraryPagination.pageCount(total: 64), 2)
        XCTAssertEqual(LibraryPagination.pageCount(total: 65), 3)
    }

    func testRangesAndClamping() {
        XCTAssertEqual(LibraryPagination.range(total: 503, page: 0), 0..<32)
        XCTAssertEqual(LibraryPagination.range(total: 503, page: 1), 32..<64)
        XCTAssertEqual(LibraryPagination.range(total: 503, page: 16), 480..<503)
        XCTAssertEqual(LibraryPagination.range(total: 61, page: 99), 32..<61)
        XCTAssertEqual(LibraryPagination.clampedPage(-5, total: 61), 0)
        XCTAssertEqual(LibraryPagination.clampedPage(99, total: 61), 1)
    }

    func testRangeLabels() {
        XCTAssertEqual(
            LibraryPagination.rangeLabel(total: 503, page: 0, localization: english),
            "1–32 of 503"
        )
        XCTAssertEqual(
            LibraryPagination.rangeLabel(total: 503, page: 1, localization: english),
            "33–64 of 503"
        )
        XCTAssertEqual(
            LibraryPagination.rangeLabel(total: 503, page: 16, localization: english),
            "481–503 of 503"
        )
        XCTAssertEqual(
            LibraryPagination.rangeLabel(total: 12, page: 0, localization: english),
            "1–12 of 12"
        )

        XCTAssertEqual(
            LibraryPagination.rangeLabel(total: 503, page: 0, localization: russian),
            "1–32 из 503"
        )
        XCTAssertEqual(
            LibraryPagination.rangeLabel(total: 503, page: 1, localization: russian),
            "33–64 из 503"
        )
        XCTAssertEqual(
            LibraryPagination.rangeLabel(total: 503, page: 16, localization: russian),
            "481–503 из 503"
        )
        XCTAssertEqual(
            LibraryPagination.rangeLabel(total: 12, page: 0, localization: russian),
            "1–12 из 12"
        )
    }
}
