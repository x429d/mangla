import SwiftUI

struct ReaderView: View {
    let session: ReadingSession
    @State private var isFullScreen = false

    var body: some View {
        ZStack {
            ReaderBackdrop()

            canvas
                .ignoresSafeArea()

            if session.isLoadingChapter {
                loadingOverlay
            }

            VStack(spacing: 0) {
                ReaderTopHUD(
                    session: session,
                    leadingInset: isFullScreen ? 0 : 70
                )

                Spacer(minLength: 0)

                EndOfChapterPill(session: session)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                ReaderBottomHUD(session: session)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
            .allowsHitTesting(!session.isLoadingChapter)

            ReaderToast(session: session)
        }
        .background(Theme.readerBackground)
        .onAppear {
            isFullScreen = WindowChrome.isFullScreen
            session.chrome.hideAll()
            WindowChrome.setTrafficLightsHidden(true)
            NSCursor.arrow.set()
            DispatchQueue.main.async {
                session.bridge.focus()
            }
        }
        .onDisappear {
            session.chrome.hideAll()
            WindowChrome.setTrafficLightsHidden(false)
            NSCursor.arrow.set()
            NSCursor.setHiddenUntilMouseMoves(false)
        }
        .onChange(of: session.chrome.isTopVisible) { _, visible in
            WindowChrome.setTrafficLightsHidden(!visible)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
            WindowChrome.setTrafficLightsHidden(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
            WindowChrome.setTrafficLightsHidden(!session.chrome.isTopVisible)
        }
    }

    @ViewBuilder
    private var canvas: some View {
        switch session.layoutMode {
        case .single, .spread:
            GeometryReader { geometry in
                PageCanvasRepresentable(
                    session: session,
                    slots: session.currentDisplaySlots,
                    fitMode: session.fitMode,
                    viewport: geometry.size
                )
                .id("page-\(session.id)-\(session.chapter.id)-\(session.layoutMode.rawValue)")
            }
        case .webtoon:
            GeometryReader { geometry in
                WebtoonCanvasRepresentable(
                    session: session,
                    pages: session.pageSlots,
                    seek: session.seekRequest,
                    viewport: geometry.size
                )
                .id("webtoon-\(session.id)-\(session.chapter.id)")
            }
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Загрузка главы")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
        }
    }
}

struct ReaderBackdrop: View {
    var body: some View {
        ZStack {
            Theme.readerBackground
            RadialGradient(
                colors: [Color.white.opacity(0.035), .clear],
                center: .center,
                startRadius: 60,
                endRadius: 900
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - End of chapter

struct EndOfChapterPill: View {
    let session: ReadingSession

    private var isAtEnd: Bool {
        session.chrome.isBottomVisible
            && !session.isLoadingChapter
            && session.totalPages > 0
            && session.currentPageIndex >= session.totalPages - 1
    }

    var body: some View {
        if isAtEnd {
            Button {
                session.nextChapter()
            } label: {
                HStack(spacing: 8) {
                    Text("Следующая глава")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule().strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(Theme.spring, value: isAtEnd)
        }
    }
}

// MARK: - Toast

struct ReaderToast: View {
    let session: ReadingSession

    var body: some View {
        VStack {
            if let toast = session.toast {
                Text(toast)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                    .padding(.top, 76)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Theme.spring, value: session.toast)
        .allowsHitTesting(false)
    }
}
