import AppKit
import XCTest

@testable import Mangla

final class ReaderShortcutsTests: XCTestCase {
    private func command(
        _ keyCode: UInt16,
        _ modifiers: NSEvent.ModifierFlags = [],
        layout: LayoutMode = .single
    ) -> ReaderKeyCommand? {
        ReaderShortcuts.command(
            keyCode: keyCode,
            modifiers: modifiers,
            layoutMode: layout
        )
    }

    func testArrowKeysAreVisualPageTurns() {
        XCTAssertEqual(command(123), .pageLeft)
        XCTAssertEqual(command(124), .pageRight)
        XCTAssertEqual(command(0), .pageLeft)
        XCTAssertEqual(command(2), .pageRight)
        XCTAssertEqual(command(38), .pageForward)
        XCTAssertEqual(command(40), .pageBackward)
        XCTAssertEqual(command(43), .pageBackward)
        XCTAssertEqual(command(47), .pageForward)
    }

    func testSpaceAndPageKeysScrollByAScreen() {
        XCTAssertEqual(command(49), .screenForward)
        XCTAssertEqual(command(49, .shift), .screenBackward)
        XCTAssertEqual(command(121), .screenForward)
        XCTAssertEqual(command(116), .screenBackward)
    }

    func testVerticalArrowsAreLeftToNativeScrollingInWebtoon() {
        XCTAssertEqual(command(125, layout: .spread), .screenForward)
        XCTAssertEqual(command(126, layout: .spread), .screenBackward)
        XCTAssertNil(command(125, layout: .webtoon))
        XCTAssertNil(command(126, layout: .webtoon))
    }

    func testChapterKeys() {
        XCTAssertEqual(command(33), .chapterBackward)
        XCTAssertEqual(command(30), .chapterForward)
        XCTAssertEqual(command(123, .command), .chapterBackward)
        XCTAssertEqual(command(124, .command), .chapterForward)
    }

    func testLayoutAndFitKeys() {
        XCTAssertEqual(command(18), .layout(.single))
        XCTAssertEqual(command(19), .layout(.spread))
        XCTAssertEqual(command(20), .layout(.webtoon))
        XCTAssertEqual(command(4), .fit(.fitHeight))
        XCTAssertEqual(command(13), .fit(.fitWidth))
        XCTAssertEqual(command(31), .fit(.original))
        XCTAssertNil(command(4, layout: .webtoon))
    }

    func testDirectionAndFullScreenKeys() {
        XCTAssertEqual(command(17), .toggleDirection)
        XCTAssertNil(command(17, layout: .webtoon))
        XCTAssertEqual(command(3), .toggleFullScreen)
    }

    func testZoomKeys() {
        XCTAssertEqual(command(24), .zoomIn)
        XCTAssertEqual(command(27), .zoomOut)
        XCTAssertEqual(command(69), .zoomIn)
        XCTAssertEqual(command(78), .zoomOut)
        XCTAssertEqual(command(29), .resetZoom)
    }

    func testHelpKeysForUSAndRussianLayouts() {
        XCTAssertEqual(command(44), .toggleHelp)
        XCTAssertEqual(command(26, .shift), .toggleHelp)
        XCTAssertNil(command(26))
        XCTAssertTrue(ReaderShortcuts.isHelpKey(keyCode: 44, modifiers: []))
        XCTAssertTrue(ReaderShortcuts.isHelpKey(keyCode: 26, modifiers: .shift))
        XCTAssertFalse(ReaderShortcuts.isHelpKey(keyCode: 26, modifiers: []))
    }

    func testCommandAndOptionCombinationsAreNotSwallowed() {
        XCTAssertNil(command(0, .command))
        XCTAssertNil(command(123, .option))
        XCTAssertNil(command(123, .control))
        XCTAssertEqual(command(5), .pageEntry)
        XCTAssertEqual(command(53), .close)
    }

    func testDiscreteCommandsDoNotRepeat() {
        XCTAssertFalse(ReaderKeyCommand.pageLeft.allowsKeyRepeat)
        XCTAssertFalse(ReaderKeyCommand.chapterForward.allowsKeyRepeat)
        XCTAssertFalse(ReaderKeyCommand.screenForward.allowsKeyRepeat)
        XCTAssertTrue(ReaderKeyCommand.zoomIn.allowsKeyRepeat)
    }
}
