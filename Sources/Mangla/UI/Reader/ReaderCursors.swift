import AppKit

/// Cursor feedback for the reader's click zones and drag-to-pan surface.
enum ReaderCursorStyle: Equatable, Sendable {
    case arrow
    case pointingHand
    case openHand
    case closedHand

    var cursor: NSCursor {
        switch self {
        case .arrow: .arrow
        case .pointingHand: .pointingHand
        case .openHand: .openHand
        case .closedHand: .closedHand
        }
    }
}

@MainActor
enum ReaderCursors {
    static func apply(_ style: ReaderCursorStyle) {
        let target = style.cursor
        if NSCursor.current !== target {
            target.set()
        }
    }

    static func style(for zone: ReaderSideZone, canPan: Bool) -> ReaderCursorStyle {
        if canPan { return .openHand }
        return zone == .middle ? .arrow : .pointingHand
    }
}
