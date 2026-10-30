import XCTest

@testable import Mangla

final class ReaderChromeStateTests: XCTestCase {
    @MainActor
    func testInitialSidebarIsHidden() {
        let chrome = ReaderChromeState()
        XCTAssertFalse(chrome.isSideVisible)
    }

    @MainActor
    func testLeftEdgeRevealsSidebar() {
        let chrome = ReaderChromeState(hideDelay: .milliseconds(10))
        chrome.updatePointer(xFromLeft: 6)
        XCTAssertTrue(chrome.isSideVisible)
    }

    @MainActor
    func testPanelWidthDoesNotRevealSidebar() {
        let chrome = ReaderChromeState(hideDelay: .milliseconds(10))
        chrome.updatePointer(xFromLeft: 12)
        XCTAssertFalse(chrome.isSideVisible, "The sidebar must not open until the pointer is at the edge")

        chrome.updatePointer(xFromLeft: 200)
        XCTAssertFalse(chrome.isSideVisible, "Only the narrow left strip opens the sidebar")
    }

    @MainActor
    func testLeavingLeftEdgeHidesSidebar() async {
        let chrome = ReaderChromeState(hideDelay: .milliseconds(10))
        chrome.updatePointer(xFromLeft: 6)
        XCTAssertTrue(chrome.isSideVisible)

        chrome.updatePointer(xFromLeft: 500)
        XCTAssertTrue(chrome.isSideVisible, "The panel should linger briefly")
        await chrome.waitForPendingSideHide()
        XCTAssertFalse(chrome.isSideVisible)
    }

    @MainActor
    func testOpenSidebarStaysWhilePointerIsOverIt() async {
        let chrome = ReaderChromeState(hideDelay: .milliseconds(10))
        chrome.updatePointer(xFromLeft: 6)
        chrome.updatePointer(xFromLeft: 200)

        await chrome.waitForPendingSideHide()
        XCTAssertTrue(chrome.isSideVisible)
    }

    @MainActor
    func testHoverKeepsSidebarVisible() async {
        let chrome = ReaderChromeState(hideDelay: .milliseconds(10))
        chrome.updatePointer(xFromLeft: 6)
        chrome.updatePointer(xFromLeft: 500)
        chrome.setSideHovered(true)

        await chrome.waitForPendingSideHide()
        XCTAssertTrue(chrome.isSideVisible)

        chrome.setSideHovered(false)
        await chrome.waitForPendingSideHide()
        XCTAssertFalse(chrome.isSideVisible)
    }

    @MainActor
    func testPointerExitHidesSidebar() async {
        let chrome = ReaderChromeState(hideDelay: .milliseconds(10))
        chrome.updatePointer(xFromLeft: 6)
        XCTAssertTrue(chrome.isSideVisible)

        chrome.pointerExited()
        await chrome.waitForPendingSideHide()
        XCTAssertFalse(chrome.isSideVisible)
    }
}
