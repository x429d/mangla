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
}
