import XCTest

@testable import Mangla

final class WindowTitlebarTests: XCTestCase {
    private let height: CGFloat = 900

    private func action(atY y: CGFloat, x: CGFloat = 400, preference: String? = "Maximize")
        -> WindowTitlebar.DoubleClickAction
    {
        WindowTitlebar.doubleClickAction(
            at: CGPoint(x: x, y: y),
            windowHeight: height,
            isFullScreen: false,
            systemPreference: preference
        )
    }

    func testDoubleClickInTopStripZooms() {
        XCTAssertEqual(action(atY: height - 4), .zoom)
        XCTAssertEqual(action(atY: height - WindowTitlebar.stripHeight + 1), .zoom)
    }

    func testDoubleClickBelowStripIsIgnored() {
        XCTAssertEqual(action(atY: height - WindowTitlebar.stripHeight - 1), .ignore)
        XCTAssertEqual(action(atY: height / 2), .ignore)
    }

    func testDoubleClickOnWindowControlsIsIgnored() {
        XCTAssertEqual(action(atY: height - 4, x: 20), .ignore)
        XCTAssertEqual(action(atY: height - 4, x: WindowTitlebar.controlsWidth), .ignore)
        XCTAssertEqual(action(atY: height - 4, x: WindowTitlebar.controlsWidth + 1), .zoom)
    }

    func testSystemPreferenceSelectsMinimize() {
        XCTAssertEqual(action(atY: height - 4, preference: "Minimize"), .minimize)
    }

    func testSystemPreferenceSelectsNothing() {
        XCTAssertEqual(action(atY: height - 4, preference: "None"), .ignore)
    }

    func testMissingPreferenceZoomsLikeTheSystemDefault() {
        XCTAssertEqual(action(atY: height - 4, preference: nil), .zoom)
    }

    func testFullScreenIgnoresDoubleClick() {
        XCTAssertEqual(
            WindowTitlebar.doubleClickAction(
                at: CGPoint(x: 400, y: height - 4),
                windowHeight: height,
                isFullScreen: true,
                systemPreference: "Maximize"
            ),
            .ignore
        )
    }
}
