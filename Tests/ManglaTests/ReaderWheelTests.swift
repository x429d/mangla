import AppKit
import XCTest

@testable import Mangla

final class ReaderWheelTests: XCTestCase {
    private func event(_ wheel1: Int32, modifier: CGEventFlags = []) throws -> NSEvent {
        let cg = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: wheel1,
            wheel2: 0,
            wheel3: 0
        ))
        cg.flags = modifier
        return try XCTUnwrap(NSEvent(cgEvent: cg))
    }

    @MainActor
    private func makeScrollView() -> ReaderScrollView {
        let scroll = ReaderScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scroll.pageWheelEnabled = true
        return scroll
    }

    @MainActor
    func testWheelDirectionsAndGating() throws {
        let down = try event(-1)
        let downScroll = makeScrollView()
        var downSteps: [Bool] = []
        downScroll.onPageStep = { downSteps.append($0) }
        downScroll.scrollWheel(with: down)
        XCTAssertEqual(downSteps, [true], "Wheel down should move forward")

        let up = try event(1)
        let upScroll = makeScrollView()
        var upSteps: [Bool] = []
        upScroll.onPageStep = { upSteps.append($0) }
        upScroll.scrollWheel(with: up)
        XCTAssertEqual(upSteps, [false], "Wheel up should move backward")

        let disabled = makeScrollView()
        disabled.pageWheelEnabled = false
        var disabledSteps: [Bool] = []
        disabled.onPageStep = { disabledSteps.append($0) }
        disabled.scrollWheel(with: down)
        XCTAssertTrue(disabledSteps.isEmpty)

        let zoomed = makeScrollView()
        zoomed.setMagnification(2, centeredAt: .zero)
        var zoomedSteps: [Bool] = []
        zoomed.onPageStep = { zoomedSteps.append($0) }
        zoomed.scrollWheel(with: down)
        XCTAssertTrue(zoomedSteps.isEmpty, "Zoomed content should scroll, not flip")
    }

    @MainActor
    func testCommandWheelZooms() throws {
        let scroll = makeScrollView()
        let before = scroll.magnification
        scroll.scrollWheel(with: try event(3, modifier: .maskCommand))
        XCTAssertGreaterThan(scroll.magnification, before)
    }

    @MainActor
    func testCanPanAtZoom() {
        let scroll = makeScrollView()
        XCTAssertFalse(scroll.canPan)
        scroll.setMagnification(2.5, centeredAt: .zero)
        XCTAssertTrue(scroll.canPan)
    }
}
