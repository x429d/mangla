import CoreGraphics

enum ReaderClickAction: Equatable, Sendable {
    case previous
    case next
    case none
}

enum ReaderSideZone: Equatable, Sendable {
    case left
    case middle
    case right
}

/// Geometry for the reader's click zones and page-turn animation direction.
///
/// The left and right thirds of the viewport turn pages; the middle third is
/// reserved for smart zoom on double click.
enum ReaderInteraction {
    static let sideZoneFraction: CGFloat = 1.0 / 3.0

    static func sideZone(x: CGFloat, width: CGFloat) -> ReaderSideZone {
        guard width > 1, x.isFinite, x >= 0, x <= width else { return .middle }
        let fraction = x / width

        if fraction < sideZoneFraction { return .left }
        if fraction > 1 - sideZoneFraction { return .right }
        return .middle
    }

    static func clickAction(
        x: CGFloat,
        width: CGFloat,
        direction: ReadingDirection
    ) -> ReaderClickAction {
        switch sideZone(x: x, width: width) {
        case .left:
            return direction == .rtl ? .next : .previous
        case .right:
            return direction == .rtl ? .previous : .next
        case .middle:
            return .none
        }
    }

    /// In RTL the next page enters from the left, so the visual direction is
    /// mirrored relative to LTR.
    static func comesFromRight(movingForward: Bool, direction: ReadingDirection) -> Bool {
        movingForward != (direction == .rtl)
    }
}
