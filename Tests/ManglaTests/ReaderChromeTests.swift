import XCTest

@testable import Mangla

final class ReaderChromeStateTests: XCTestCase {
    @MainActor
    func testInitialPanelsAreHidden() {
        let chrome = ReaderChromeState()
        XCTAssertFalse(chrome.isSideVisible)
        XCTAssertFalse(chrome.isBottomVisible)
    }

    @MainActor
    func testLeftEdgeRevealsSidebarOnly() {
        let chrome = ReaderChromeState(hideDelay: .milliseconds(10))
        chrome.updatePointer(xFromLeft: 12, yFromTop: 400, height: 900)
        XCTAssertTrue(chrome.isSideVisible)
        XCTAssertFalse(chrome.isBottomVisible)
    }

    @MainActor
    func testPanelWidthDoesNotRevealSidebar() {
        let chrome = ReaderChromeState(hideDelay: .milliseconds(10))
        chrome.updatePointer(xFromLeft: 200, yFromTop: 400, height: 900)
        XCTAssertFalse(chrome.isSideVisible, "Only the narrow left strip opens the sidebar")
    }

    @MainActor
    func testLeavingLeftEdgeHidesSidebar() async {
        let chrome = ReaderChromeState(hideDelay: .milliseconds(10))
        chrome.updatePointer(xFromLeft: 12, yFromTop: 400, height: 900)
        XCTAssertTrue(chrome.isSideVisible)

        chrome.updatePointer(xFromLeft: 500, yFromTop: 400, height: 900)
        XCTAssertTrue(chrome.isSideVisible, "The panel should linger briefly")
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(chrome.isSideVisible)
        XCTAssertFalse(chrome.isBottomVisible)
    }

    @MainActor
    func testOpenSidebarStaysWhilePointerIsOverIt() async {
        let chrome = ReaderChromeState(hideDelay: .milliseconds(10))
        chrome.updatePointer(xFromLeft: 12, yFromTop: 400, height: 900)
        chrome.updatePointer(xFromLeft: 200, yFromTop: 400, height: 900)

        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(chrome.isSideVisible)
    }

    @MainActor
    func testBottomEdgeDoesNotTouchSidebar() async {
        let chrome = ReaderChromeState(hideDelay: .milliseconds(10))
        chrome.updatePointer(xFromLeft: 12, yFromTop: 400, height: 900)
        XCTAssertTrue(chrome.isSideVisible)

        chrome.updatePointer(xFromLeft: 500, yFromTop: 870, height: 900)
        XCTAssertTrue(chrome.isBottomVisible)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(chrome.isSideVisible)
        XCTAssertTrue(chrome.isBottomVisible)
    }

    @MainActor
    func testHoverKeepsSidebarVisible() async {
        let chrome = ReaderChromeState(hideDelay: .milliseconds(10))
        chrome.updatePointer(xFromLeft: 12, yFromTop: 400, height: 900)
        chrome.updatePointer(xFromLeft: 500, yFromTop: 400, height: 900)
        chrome.setSideHovered(true)

        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(chrome.isSideVisible)

        chrome.setSideHovered(false)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(chrome.isSideVisible)
    }

    @MainActor
    func testPointerExitHidesPanels() async {
        let chrome = ReaderChromeState(hideDelay: .milliseconds(10))
        chrome.updatePointer(xFromLeft: 12, yFromTop: 870, height: 900)
        XCTAssertTrue(chrome.isSideVisible)
        XCTAssertTrue(chrome.isBottomVisible)

        chrome.pointerExited()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(chrome.isBottomVisible)
        XCTAssertFalse(chrome.isSideVisible)
    }
}
