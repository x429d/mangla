import SwiftUI

/// Native-looking window controls for the app's custom titlebar areas.
/// The real traffic lights stay hidden so the controls can sit inside the
/// sidebar with a comfortable inset in every mode, including fullscreen.
struct WindowTrafficLights: View {
    @State private var isFullScreen = WindowChrome.isFullScreen
    @State private var hovering = false

    private let closeColor = Color(red: 1.00, green: 0.37, blue: 0.34)
    private let minimizeColor = Color(red: 1.00, green: 0.74, blue: 0.18)
    private let zoomColor = Color(red: 0.16, green: 0.78, blue: 0.25)

    var body: some View {
        HStack(spacing: 8) {
            button(
                color: closeColor,
                symbol: "xmark",
                help: t(.closeWindow)
            ) {
                WindowChrome.closeWindow()
            }

            button(
                color: minimizeColor,
                symbol: "minus",
                help: t(.minimizeWindow)
            ) {
                WindowChrome.miniaturizeWindow()
            }
            .disabled(isFullScreen)
            .opacity(isFullScreen ? 0.35 : 1)

            button(
                color: zoomColor,
                symbol: isFullScreen
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                help: isFullScreen ? t(.exitFullScreenHelp) : t(.fullScreenHelp)
            ) {
                WindowChrome.toggleFullScreen()
            }
        }
        .onHover { hovering = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
    }

    private func button(
        color: Color,
        symbol: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color)
                if hovering {
                    Image(systemName: symbol)
                        .font(.system(size: 6.5, weight: .heavy))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
            }
            .frame(width: 12, height: 12)
            .overlay(
                Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // Window controls should never take keyboard focus and show the
        // blue focus ring when the app launches.
        .focusable(false)
        .focusEffectDisabled()
        .help(help)
        .accessibilityLabel(Text(help))
    }
}
