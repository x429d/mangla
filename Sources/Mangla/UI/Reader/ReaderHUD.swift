import SwiftUI

// MARK: - HUD controls

struct HUDIconButton: View {
    let symbol: String
    var help: String = ""
    var size: CGFloat = 28
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.39, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )
                .contentShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Left sidebar

/// Geometry shared with the canvases so the cursor can become a normal arrow
/// over the open panel without measuring SwiftUI frames on every mouse move.
enum ReaderSidebarLayout {
    static let width: CGFloat = 250
    static let horizontalPadding: CGFloat = 14
    /// Same top inset as the library so the window buttons line up.
    static let topInset: CGFloat = 42
    static let hitWidth: CGFloat = width
}

struct ReaderSidebar: View {
    let session: ReadingSession

    var body: some View {
        VStack(spacing: 0) {
            WindowTrafficLights()
                .padding(.leading, 30)
                .padding(.top, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: ReaderSidebarLayout.topInset, alignment: .top)

            panel
                .padding(.horizontal, ReaderSidebarLayout.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: ReaderSidebarLayout.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            // One solid color for the whole sidebar, including the strip
            // with the window buttons. A translucent material made the top
            // of the panel pick up the page color and look like a separate
            // native titlebar.
            Rectangle()
                .fill(Theme.background)
                .allowsHitTesting(false)
                .shadow(color: .black.opacity(0.45), radius: 22, x: 8, y: 0)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1)
                .allowsHitTesting(false)
        }
        .opacity(session.chrome.isSideVisible ? 1 : 0)
        .offset(x: session.chrome.isSideVisible ? 0 : -26)
        .animation(.smooth(duration: 0.22), value: session.chrome.isSideVisible)
        .allowsHitTesting(session.chrome.isSideVisible)
        .onHover { hovering in
            session.chrome.setSideHovered(hovering)
            if hovering {
                NSCursor.arrow.set()
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            backButton

            divider

            titleBlock

            divider

            layoutSection

            Spacer().frame(height: 8)

            controlRow(label: t(.fit)) { fitMenu }

            Spacer().frame(height: 8)

            controlRow(label: t(.direction)) { directionPicker }
                .disabled(session.layoutMode == .webtoon)
                .opacity(session.layoutMode == .webtoon ? 0.38 : 1)

            Spacer().frame(height: 8)

            controlRow(label: t(.zoom)) { zoomControls }

            Spacer(minLength: 16)

            pageSection

            divider

            footer
        }
    }

    // MARK: Header

    private var backButton: some View {
        Button {
            session.dismiss()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .bold))
                Text(t(.library))
                    .font(.system(size: 10.5, weight: .semibold))
                Spacer(minLength: 4)
                Text("Esc")
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(t(.backToLibraryHelp))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .truncationMode(.middle)

            if let chapterSuffix {
                Text(chapterSuffix)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 62, alignment: .top)
    }

    /// Chapter folders often repeat the manga name; avoid showing it twice.
    private var chapterSuffix: String? {
        let chapter = session.chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chapter.isEmpty else { return nil }
        guard chapter.localizedCaseInsensitiveCompare(title) != .orderedSame else { return nil }
        return chapter
    }

    // MARK: Controls

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(t(.mode))

            HStack(spacing: 2) {
                ForEach(LayoutMode.allCases) { mode in
                    Button {
                        session.layoutMode = mode
                    } label: {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(
                                session.layoutMode == mode ? Theme.textPrimary : Theme.textTertiary
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(
                                        session.layoutMode == mode
                                            ? Color.white.opacity(0.13)
                                            : .clear
                                    )
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("\(mode.title) (\(mode.shortcutKey))")
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.18))
            )
        }
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
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(t(.fitModeHelp))
    }

    private var directionPicker: some View {
        HStack(spacing: 2) {
            ForEach(ReadingDirection.allCases) { direction in
                Button {
                    session.direction = direction
                } label: {
                    Text(direction.shortTitle)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(
                            session.direction == direction ? Theme.textPrimary : Theme.textTertiary
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    session.direction == direction
                                        ? Color.white.opacity(0.13)
                                        : .clear
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("\(direction.title) (T)")
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.18))
        )
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            HUDIconButton(symbol: "minus", help: t(.zoomOutHelp), size: 24) {
                session.bridge.zoomOut()
            }

            Button {
                session.resetZoom()
            } label: {
                Text("\(Int((session.zoom * 100).rounded()))%")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(t(.resetZoomHelp))

            HUDIconButton(symbol: "plus", help: t(.zoomInHelp), size: 24) {
                session.bridge.zoomIn()
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.18))
        )
    }

    // MARK: Pages

    private var pageSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                sectionLabel(t(.page))

                Spacer(minLength: 4)

                Button {
                    session.beginPageEntry()
                } label: {
                    Text(session.currentPageLabel)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(t(.goToPageHelp))
            }

            PageScrubber(
                pages: session.pageSlots,
                currentPage: session.currentPageIndex,
                onSeek: { session.goToPage($0) }
            )
            .frame(height: 22)

            HStack(spacing: 6) {
                HUDIconButton(
                    symbol: "backward.end.fill",
                    help: t(.previousChapterHelp)
                ) {
                    session.previousChapter()
                }

                HUDIconButton(
                    symbol: "chevron.left",
                    help: session.direction == .rtl
                        ? t(.nextPageLeftHelp)
                        : t(.previousPageLeftHelp)
                ) {
                    if session.direction == .rtl {
                        session.next()
                    } else {
                        session.previous()
                    }
                }

                Spacer(minLength: 0)

                HUDIconButton(
                    symbol: "chevron.right",
                    help: session.direction == .rtl
                        ? t(.previousPageRightHelp)
                        : t(.nextPageRightHelp)
                ) {
                    if session.direction == .rtl {
                        session.previous()
                    } else {
                        session.next()
                    }
                }

                HUDIconButton(
                    symbol: "forward.end.fill",
                    help: t(.nextChapterHelp)
                ) {
                    session.nextChapter()
                }
            }
        }
        .zIndex(1)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            HUDIconButton(
                symbol: "questionmark",
                help: t(.controlsHelp)
            ) {
                session.showHelp()
            }

            HUDIconButton(
                symbol: "arrow.up.left.and.arrow.down.right",
                help: t(.fullScreenHelp)
            ) {
                WindowChrome.toggleFullScreen()
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 8.5, weight: .bold, design: .rounded))
            .tracking(0.6)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(Theme.textTertiary)
    }

    private func controlRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            sectionLabel(label)
                .frame(width: 82, alignment: .leading)
            content()
        }
        .frame(height: 28)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 10)
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
