import XCTest

@testable import Mangla

final class ReaderInteractionTests: XCTestCase {
    func testLTRClickZones() {
        XCTAssertEqual(
            ReaderInteraction.clickAction(x: 100, width: 900, direction: .ltr),
            .previous
        )
        XCTAssertEqual(
            ReaderInteraction.clickAction(x: 800, width: 900, direction: .ltr),
            .next
        )
        XCTAssertEqual(
            ReaderInteraction.clickAction(x: 450, width: 900, direction: .ltr),
            .none
        )
    }

    func testRTLClickZonesAreMirrored() {
        XCTAssertEqual(
            ReaderInteraction.clickAction(x: 100, width: 900, direction: .rtl),
            .next
        )
        XCTAssertEqual(
            ReaderInteraction.clickAction(x: 800, width: 900, direction: .rtl),
            .previous
        )
        XCTAssertEqual(
            ReaderInteraction.clickAction(x: 450, width: 900, direction: .rtl),
            .none
        )
    }

    func testExactThirdBoundariesAreNeutral() {
        XCTAssertEqual(
            ReaderInteraction.clickAction(x: 300, width: 900, direction: .ltr),
            .none
        )
        XCTAssertEqual(
            ReaderInteraction.clickAction(x: 600, width: 900, direction: .ltr),
            .none
        )
    }

    func testInvalidWidthProducesNoAction() {
        XCTAssertEqual(
            ReaderInteraction.clickAction(x: 0, width: 0, direction: .ltr),
            .none
        )
    }

    func testPageTurnAnimationDirection() {
        XCTAssertTrue(ReaderInteraction.comesFromRight(movingForward: true, direction: .ltr))
        XCTAssertFalse(ReaderInteraction.comesFromRight(movingForward: false, direction: .ltr))
        XCTAssertFalse(ReaderInteraction.comesFromRight(movingForward: true, direction: .rtl))
        XCTAssertTrue(ReaderInteraction.comesFromRight(movingForward: false, direction: .rtl))
    }

    func testScrollAxisNeedsADominantHorizontalDelta() {
        XCTAssertEqual(ReaderInteraction.scrollAxis(deltaX: 40, deltaY: 4), .horizontal)
        XCTAssertEqual(ReaderInteraction.scrollAxis(deltaX: 4, deltaY: 40), .vertical)
        XCTAssertEqual(ReaderInteraction.scrollAxis(deltaX: 10, deltaY: 10), .vertical)
        XCTAssertEqual(ReaderInteraction.scrollAxis(deltaX: .nan, deltaY: 10), .vertical)
    }

    @MainActor
    func testCursorStylePrefersPanningWhenPossible() {
        XCTAssertEqual(ReaderCursors.style(for: .middle, canPan: false), .arrow)
        XCTAssertEqual(ReaderCursors.style(for: .left, canPan: false), .pointingHand)
        XCTAssertEqual(ReaderCursors.style(for: .right, canPan: true), .openHand)
    }

    func testPageIndexParsing() {
        XCTAssertEqual(ReaderInteraction.pageIndex(from: "12", pageCount: 20), 11)
        XCTAssertEqual(ReaderInteraction.pageIndex(from: " 1 ", pageCount: 20), 0)
        XCTAssertEqual(ReaderInteraction.pageIndex(from: "20", pageCount: 20), 19)
        XCTAssertNil(ReaderInteraction.pageIndex(from: "0", pageCount: 20))
        XCTAssertNil(ReaderInteraction.pageIndex(from: "21", pageCount: 20))
        XCTAssertNil(ReaderInteraction.pageIndex(from: "", pageCount: 20))
        XCTAssertNil(ReaderInteraction.pageIndex(from: "abc", pageCount: 20))
        XCTAssertNil(ReaderInteraction.pageIndex(from: "1", pageCount: 0))
    }
}
