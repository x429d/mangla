import SwiftUI

// MARK: - HUD chrome

struct HUDChrome: ViewModifier {
    var corner: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(Color.black.opacity(0.30))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 22, y: 10)
    }
}

struct HUDIconButton: View {
    let symbol: String
    var help: String = ""
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(active ? Color.white.opacity(0.12) : Color.white.opacity(0.045))
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Top HUD

struct ReaderTopHUD: View {
    let session: ReadingSession

    var body: some View {
        HStack(spacing: 10) {
            Button {
                session.dismiss()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text("Библиотека")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )
            }
            .buttonStyle(.plain)
            .help("Вернуться в библиотеку (Esc)")

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(session.chapterTitle)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: 300, alignment: .leading)

            Spacer(minLength: 8)

            layoutPicker
            fitMenu
                .disabled(session.layoutMode == .webtoon)
                .opacity(session.layoutMode == .webtoon ? 0.38 : 1)
            directionButton
                .disabled(session.layoutMode == .webtoon)
                .opacity(session.layoutMode == .webtoon ? 0.38 : 1)
            zoomButton
            HUDIconButton(
                symbol: "arrow.up.left.and.arrow.down.right",
                help: "Полный экран (F)"
            ) {
                WindowChrome.toggleFullScreen()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .modifier(HUDChrome())
        .opacity(session.chrome.isTopVisible ? 1 : 0)
        .offset(y: session.chrome.isTopVisible ? 0 : -12)
        .animation(.smooth(duration: 0.22), value: session.chrome.isTopVisible)
        .allowsHitTesting(session.chrome.isTopVisible)
        .onHover { hovering in
            session.chrome.setTopHovered(hovering)
            if hovering {
                NSCursor.arrow.set()
            }
        }
    }

    private var layoutPicker: some View {
        HStack(spacing: 2) {
            ForEach(LayoutMode.allCases) { mode in
                Button {
                    session.layoutMode = mode
                } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(
                            session.layoutMode == mode ? Theme.textPrimary : Theme.textTertiary
                        )
                        .frame(width: 30, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(session.layoutMode == mode ? Color.white.opacity(0.13) : .clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(mode.title)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.18))
        )
    }

    private var fitMenu: some View {
        Menu {
            ForEach(FitMode.allCases) { mode in
                Button {
                    session.fitMode = mode
                } label: {
                    Label(mode.title, systemImage: mode.symbol)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: session.fitMode.symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(session.fitMode.shortTitle)
                    .font(.system(size: 10, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Режим вписывания")
    }

    private var directionButton: some View {
        Button {
            session.direction = session.direction == .rtl ? .ltr : .rtl
        } label: {
            Text(session.direction.shortTitle)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 36, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )
        }
        .buttonStyle(.plain)
        .help(session.direction.title)
    }

    private var zoomButton: some View {
        Button {
            session.resetZoom()
        } label: {
            Text("\(Int((session.zoom * 100).rounded()))%")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 48, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )
        }
        .buttonStyle(.plain)
        .help("Сбросить масштаб (⌘0)")
    }
}

// MARK: - Bottom HUD

struct ReaderBottomHUD: View {
    let session: ReadingSession

    var body: some View {
        HStack(spacing: 9) {
            HUDIconButton(symbol: "backward.end.fill", help: "Предыдущая глава") {
                session.previousChapter()
            }

            HUDIconButton(
                symbol: "chevron.left",
                help: session.direction == .rtl ? "Следующая страница" : "Предыдущая страница"
            ) {
                if session.direction == .rtl {
                    session.next()
                } else {
                    session.previous()
                }
            }

            PageScrubber(
                pages: session.pageSlots,
                currentPage: session.currentPageIndex,
                onSeek: { session.goToPage($0) }
            )
            .frame(height: 24)

            Text(session.currentPageLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 94)

            HUDIconButton(
                symbol: "chevron.right",
                help: session.direction == .rtl ? "Предыдущая страница" : "Следующая страница"
            ) {
                if session.direction == .rtl {
                    session.previous()
                } else {
                    session.next()
                }
            }

            HUDIconButton(symbol: "forward.end.fill", help: "Следующая глава") {
                session.nextChapter()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 1000)
        .modifier(HUDChrome())
        .opacity(session.chrome.isBottomVisible ? 1 : 0)
        .offset(y: session.chrome.isBottomVisible ? 0 : 12)
        .animation(.smooth(duration: 0.22), value: session.chrome.isBottomVisible)
        .allowsHitTesting(session.chrome.isBottomVisible)
        .onHover { hovering in
            session.chrome.setBottomHovered(hovering)
            if hovering {
                NSCursor.arrow.set()
            }
        }
    }
}

// MARK: - Scrubber with hover preview

struct PageScrubber: View {
    let pages: [PageSlot]
    let currentPage: Int
    let onSeek: (Int) -> Void

    @State private var hoverX: CGFloat?
    @State private var hovering = false
    @State private var dragging = false
    @State private var lastSent = -1

    private var progress: CGFloat {
        let count = pages.count
        guard count > 1 else { return count == 1 ? 1 : 0 }
        let index = min(max(currentPage, 0), count - 1)
        return CGFloat(index) / CGFloat(count - 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let knobX = progress * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.13))
                    .frame(height: 3)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Theme.accentSoft, Theme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, knobX), height: 3)
                Circle()
                    .fill(Color.white)
                    .frame(width: hovering || dragging ? 13 : 10, height: hovering || dragging ? 13 : 10)
                    .offset(x: max(0, min(knobX - (hovering || dragging ? 6.5 : 5), width - 10)))
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hovering = true
                    hoverX = point.x
                case .ended:
                    hovering = false
                    if !dragging { hoverX = nil }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        hoverX = value.location.x
                        sendSeek(at: value.location.x, width: width)
                    }
                    .onEnded { _ in
                        dragging = false
                        lastSent = -1
                    }
            )
            .overlay(alignment: .topLeading) {
                if let index = previewIndex(width: width), hovering || dragging {
                    preview(index: index)
                        .offset(
                            x: max(0, min((hoverX ?? knobX) - 46, width - 92)),
                            y: -158
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        .frame(height: 24)
    }

    private func previewIndex(width: CGFloat) -> Int? {
        guard !pages.isEmpty else { return nil }
        let x = hoverX ?? progress * width
        let ratio = min(max(x / max(width, 1), 0), 1)
        let index = Int((ratio * CGFloat(max(pages.count - 1, 0))).rounded())
        return pages.indices.contains(index) ? index : nil
    }

    private func sendSeek(at x: CGFloat, width: CGFloat) {
        guard !pages.isEmpty else { return }
        let ratio = min(max(x / max(width, 1), 0), 1)
        let index = Int((ratio * CGFloat(max(pages.count - 1, 0))).rounded())
        guard index != lastSent else { return }
        lastSent = index
        onSeek(index)
    }

    private func preview(index: Int) -> some View {
        VStack(spacing: 4) {
            ThumbnailImage(url: pages[index].url, maxPixel: 320)
                .frame(width: 82, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
            Text("\(index + 1)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 14, y: 7)
    }
}
