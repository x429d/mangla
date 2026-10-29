import SwiftUI

/// Cheat sheet shown with `?`. It is the discoverable home for every keyboard,
/// mouse and trackpad gesture the reader supports.
struct ReaderShortcutsOverlay: View {
    let session: ReadingSession

    private struct KeyRow: Identifiable {
        var id: String { keys.joined(separator: " ") + "|" + action }
        let keys: [String]
        let action: String
    }

    private struct MouseRow: Identifiable {
        var id: String { gesture + "|" + action }
        let gesture: String
        let action: String
    }

    private var keyboardRows: [KeyRow] {
        [
            KeyRow(keys: ["←", "→", "A", "D"], action: t(.helpPageBackForward)),
            KeyRow(keys: [",", ".", "J", "K"], action: t(.helpPageReadingOrder)),
            KeyRow(keys: ["Space", "PgDn"], action: t(.helpScreenForward)),
            KeyRow(keys: ["⇧Space", "PgUp"], action: t(.helpScreenBackward)),
            KeyRow(keys: ["↑", "↓"], action: t(.helpScrollWebtoon)),
            KeyRow(keys: ["Home", "End"], action: t(.helpFirstLastPage)),
            KeyRow(keys: ["[", "]"], action: t(.helpChapterBackForward)),
            KeyRow(keys: ["⌘←", "⌘→"], action: t(.helpChapterBackForward)),
            KeyRow(keys: ["1", "2", "3"], action: t(.helpLayoutModes)),
            KeyRow(keys: ["T"], action: t(.helpDirection)),
            KeyRow(keys: ["H", "W", "O"], action: t(.helpFitModes)),
            KeyRow(keys: ["+", "−", "0"], action: t(.helpZoom)),
            KeyRow(keys: ["G"], action: t(.helpGoToPage)),
            KeyRow(keys: ["F", "⌃⌘F"], action: t(.helpFullScreen)),
            KeyRow(keys: ["?"], action: t(.helpThisSheet)),
            KeyRow(keys: ["Esc", "⌘⇧W"], action: t(.helpToLibrary)),
        ]
    }

    private var mouseRows: [MouseRow] {
        [
            MouseRow(gesture: t(.helpClickSides), action: t(.helpPageBackForward)),
            MouseRow(gesture: t(.helpDoubleClickCenter), action: t(.helpSmartZoom)),
            MouseRow(gesture: t(.helpWheel), action: t(.helpWheelAction)),
            MouseRow(gesture: t(.helpCommandWheel), action: t(.helpZoomToCursor)),
            MouseRow(gesture: t(.helpDrag), action: t(.helpDragAction)),
            MouseRow(gesture: t(.helpSideButtons), action: t(.helpPageBackForward)),
            MouseRow(gesture: t(.helpRightClick), action: t(.helpCommandMenu)),
            MouseRow(gesture: t(.helpPinch), action: t(.helpPinchAction)),
            MouseRow(gesture: t(.helpTwoFingerSwipe), action: t(.helpTwoFingerSwipeAction)),
            MouseRow(gesture: t(.helpLeftEdge), action: t(.helpLeftEdgeAction)),
        ]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.58)
                .ignoresSafeArea()
                .onTapGesture { session.hideHelp() }

            panel
                .frame(maxWidth: 720)
                .padding(24)
        }
        .transition(.opacity)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            HStack(alignment: .top, spacing: 24) {
                column(
                    title: t(.helpKeyboard),
                    symbol: "keyboard"
                ) {
                    ForEach(keyboardRows) { row in
                        keyRow(row)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Theme.stroke)
                    .frame(width: 1)

                column(
                    title: t(.helpMouse),
                    symbol: "computermouse"
                ) {
                    ForEach(mouseRows) { row in
                        mouseRow(row)
                    }
                }
                .frame(width: 286, alignment: .leading)
            }

            footer
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.44))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.55), radius: 34, y: 16)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accentSoft)
            Text(t(.helpTitle))
                .font(.system(size: 19, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.textPrimary)
            Text(t(.helpSubtitle))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 12)
            Button {
                session.hideHelp()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help(t(.helpClose))
        }
    }

    private func column<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
            }
            .foregroundStyle(Theme.accentSoft.opacity(0.9))

            content()
        }
    }

    private func keyRow(_ row: KeyRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 3) {
                ForEach(Array(row.keys.enumerated()), id: \.offset) { _, key in
                    KeyCap(text: key)
                }
            }
            .frame(width: 126, alignment: .leading)

            Text(row.action)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func mouseRow(_ row: MouseRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(row.gesture)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.86))
                .frame(width: 112, alignment: .leading)

            Text(row.action)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(t(.helpFooter))
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}

private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.textPrimary.opacity(0.88))
            .padding(.horizontal, 5)
            .frame(minWidth: 17, minHeight: 17)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.075))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}
