import CoreGraphics

/// Double-click handling for the frameless titlebar.
///
/// The window hides its native titlebar and draws its own controls inside the
/// content, so a double-click in the empty strip at the top would otherwise
/// land in SwiftUI and do nothing. macOS expects a titlebar double-click to
/// zoom the window (or minimize it, depending on the system preference).
enum WindowTitlebar {
    /// Height of the empty strip that holds the custom traffic lights. Every
    /// mode keeps its header content below this line.
    static let stripHeight: CGFloat = 36

    /// The traffic lights occupy the leading corner of the strip; a double
    /// click there belongs to the buttons, not to the titlebar.
    static let controlsWidth: CGFloat = 112

    enum DoubleClickAction: Equatable {
        case zoom
        case minimize
        case ignore
    }

    /// Resolves what a double-click should do. `point` is in window
    /// coordinates (origin at the bottom left) and `systemPreference` is the
    /// global `AppleActionOnDoubleClick` value, which defaults to zooming.
    static func doubleClickAction(
        at point: CGPoint,
        windowHeight: CGFloat,
        isFullScreen: Bool,
        systemPreference: String?
    ) -> DoubleClickAction {
        guard !isFullScreen else { return .ignore }
        guard point.y >= windowHeight - stripHeight else { return .ignore }
        guard point.x > controlsWidth else { return .ignore }

        switch systemPreference {
        case "Minimize": return .minimize
        case "None": return .ignore
        default: return .zoom
        }
    }
}
