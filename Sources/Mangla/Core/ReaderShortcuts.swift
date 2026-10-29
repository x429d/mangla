import AppKit

/// A keyboard action available inside the reader. Visual commands are mirrored
/// later according to the reading direction; logical commands always move in
/// reading order.
enum ReaderKeyCommand: Equatable, Sendable {
    case pageLeft
    case pageRight
    case pageForward
    case pageBackward
    case chapterForward
    case chapterBackward
    case firstPage
    case lastPage
    case screenForward
    case screenBackward
    case layout(LayoutMode)
    case toggleDirection
    case fit(FitMode)
    case zoomIn
    case zoomOut
    case resetZoom
    case toggleFullScreen
    case toggleHelp
    case pageEntry
    case close

    /// Page and chapter jumps are discrete: holding a key down should not race
    /// through the whole chapter at the system key-repeat rate.
    var allowsKeyRepeat: Bool {
        switch self {
        case .zoomIn, .zoomOut:
            true
        default:
            false
        }
    }
}

/// Physical key codes are used on purpose: the reader shortcuts must keep
/// working with a Russian (or any other) keyboard layout.
enum ReaderShortcuts {
    /// `/` on a US layout and Shift+7 on a Russian layout both produce `?`.
    static let helpKeyCode: UInt16 = 44
    static let shiftedHelpKeyCode: UInt16 = 26

    static func isHelpKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        if keyCode == helpKeyCode { return true }
        return keyCode == shiftedHelpKeyCode && modifiers.contains(.shift)
    }

    static func command(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        layoutMode: LayoutMode
    ) -> ReaderKeyCommand? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.option) || flags.contains(.control) {
            return nil
        }

        if flags.contains(.command) {
            switch keyCode {
            case 123: return .chapterBackward
            case 124: return .chapterForward
            default: return nil
            }
        }

        switch keyCode {
        case 53: // Esc
            return .close
        case 123: // Left
            return .pageLeft
        case 124: // Right
            return .pageRight
        case 125: // Down — page mode flips, webtoon keeps native scrolling
            return layoutMode == .webtoon ? nil : .screenForward
        case 126: // Up
            return layoutMode == .webtoon ? nil : .screenBackward
        case 0: // A
            return .pageLeft
        case 2: // D
            return .pageRight
        case 38: // J
            return .pageForward
        case 40: // K
            return .pageBackward
        case 43: // ,
            return .pageBackward
        case 47: // .
            return .pageForward
        case 49: // Space
            return flags.contains(.shift) ? .screenBackward : .screenForward
        case 121: // Page Down
            return .screenForward
        case 116: // Page Up
            return .screenBackward
        case 115: // Home
            return .firstPage
        case 119: // End
            return .lastPage
        case 33: // [
            return .chapterBackward
        case 30: // ]
            return .chapterForward
        case 18: // 1
            return .layout(.single)
        case 19: // 2
            return .layout(.spread)
        case 20: // 3
            return .layout(.webtoon)
        case 17: // T
            return layoutMode == .webtoon ? nil : .toggleDirection
        case 4: // H
            return layoutMode == .webtoon ? nil : .fit(.fitHeight)
        case 13: // W
            return layoutMode == .webtoon ? nil : .fit(.fitWidth)
        case 31: // O
            return layoutMode == .webtoon ? nil : .fit(.original)
        case 3: // F
            return .toggleFullScreen
        case 5: // G
            return .pageEntry
        case 29: // 0
            return .resetZoom
        case 27: // -
            return .zoomOut
        case 24: // =
            return .zoomIn
        case 69: // keypad +
            return .zoomIn
        case 78: // keypad -
            return .zoomOut
        case 44: // / (US layout)
            return .toggleHelp
        case 26: // 7 — Shift+7 is ? on a Russian layout
            return flags.contains(.shift) ? .toggleHelp : nil
        default:
            return nil
        }
    }
}
