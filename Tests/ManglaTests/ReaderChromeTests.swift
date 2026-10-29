import XCTest

@testable import Mangla

final class ReaderChromeStateTests: XCTestCase {
    @MainActor
    func testInitialPanelsAreHidden() {
        let chrome = ReaderChromeState()
        XCTAssertFalse(chrome.isTopVisible)
        XCTAssertFalse(chrome.isBottomVisible)
    }

    @MainActor
    func testTopEdgeRevealsTopPanelOnly() {
        let chrome = ReaderChromeState(hideDelay: .milliseconds(10))
        chrome.updatePointer(yFromTop: 24, height: 900)
        XCTAssertTrue(chrome.isTopVisible)
        XCTAssertFalse(chrome.isBottomVisible)
    }

    @MainActor
    func testLeavingTopHidesTopPanel() async {
        let chrome = ReaderChromeState(hideDelay: .milliseconds(10))
        chrome.updatePointer(yFromTop: 20, height: 900)
        XCTAssertTrue(chrome.isTopVisible)

        chrome.updatePointer(yFromTop: 500, height: 900)
        XCTAssertTrue(chrome.isTopVisible, "The panel should linger briefly")
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(chrome.isTopVisible)
        XCTAssertFalse(chrome.isBottomVisible)
    }

    @MainActor
    func testBottomEdgeDoesNotTouchTopPanel() async {
        let chrome = ReaderChromeState(hideDelay: .milliseconds(10))
        chrome.updatePointer(yFromTop: 20, height: 900)
        XCTAssertTrue(chrome.isTopVisible)

        chrome.updatePointer(yFromTop: 870, height: 900)
        XCTAssertTrue(chrome.isBottomVisible)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(chrome.isTopVisible)
        XCTAssertTrue(chrome.isBottomVisible)
    }

    @MainActor
    func testHoverKeepsPanelVisible() async {
        let chrome = ReaderChromeState(hideDelay: .milliseconds(10))
        chrome.updatePointer(yFromTop: 20, height: 900)
        chrome.updatePointer(yFromTop: 500, height: 900)
        chrome.setTopHovered(true)

        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(chrome.isTopVisible)

        chrome.setTopHovered(false)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(chrome.isTopVisible)
    }

    @MainActor
    func testPointerExitHidesBottomPanel() async {
        let chrome = ReaderChromeState(hideDelay: .milliseconds(10))
        chrome.updatePointer(yFromTop: 880, height: 900)
        XCTAssertTrue(chrome.isBottomVisible)

        chrome.pointerExited()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(chrome.isBottomVisible)
        XCTAssertFalse(chrome.isTopVisible)
    }
}
