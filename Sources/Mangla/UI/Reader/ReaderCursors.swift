import AppKit

/// Cursor feedback for the reader's click zones.
///
/// The page-turn thirds use the standard macOS pointing hand; the middle of the
/// page and the floating HUD panels keep the normal arrow.
@MainActor
enum ReaderCursors {
    static func apply(_ zone: ReaderSideZone) {
        let target: NSCursor
        switch zone {
        case .left, .right:
            target = .pointingHand
        case .middle:
            target = .arrow
        }

        if NSCursor.current !== target {
            target.set()
        }
    }
}
