import AppKit
import SwiftUI

/// Continuous vertical strip (webtoon) with a shared native magnification.
struct WebtoonCanvasRepresentable: NSViewRepresentable {
    let session: ReadingSession
    let pages: [PageSlot]
    let seek: WebtoonSeekRequest
    let viewport: CGSize

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> ReaderScrollView {
        let scrollView = ReaderScrollView()
        context.coordinator.install(in: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: ReaderScrollView, context: Context) {
        context.coordinator.update(pages: pages, seek: seek, viewport: viewport)
    }

    static func dismantleNSView(_ scrollView: ReaderScrollView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator: NSObject, ReaderCanvasControlling {
        /// Pages kept decoded around the visible one. The strip itself can hold
        /// thousands of pages; only this window is ever materialised.
        private static let loadWindowBefore = 2
        private static let loadWindowAfter = 4
        private static let retentionWindowBefore = 8
        private static let retentionWindowAfter = 8

        let session: ReadingSession

        private(set) var scrollView: ReaderScrollView?
        private let container = CanvasSurfaceView()
        private let strip = CanvasSurfaceView()
        /// Lazily created page views. Indexes outside the visited window stay
        /// `nil`, so opening a long chapter no longer builds thousands of views.
        private var pageViews: [PageContentView?] = []
        private var loadTasks: [Int: Task<Void, Never>] = [:]
        private var loadTokens: [Int: UUID] = [:]
        private var prefetchTask: Task<Void, Never>?
        private lazy var contextMenuController = ReaderContextMenuController(session: session)

        private var currentPages: [PageSlot] = []
        private var currentSources: [PageSource] = []
        private var stripLayout = WebtoonStripLayout.empty
        private var generation = 0
        private var installed = false
        private var isUpdating = false
        private var lastWidth: CGFloat = 0
        private var lastViewportHeight: CGFloat = 0
        private var lastSeekID = 0
        private var didInitialScroll = false
        private var lastVisiblePage = -1
        private var lastLoadedWindow: PageWindow?
        private var lastRetentionWindow: PageWindow?

        init(session: ReadingSession) {
            self.session = session
            super.init()
        }

        func install(in scrollView: ReaderScrollView) {
            self.scrollView = scrollView
            installed = true

            container.autoresizingMask = []
            container.onClick = { [weak self] event in self?.handleClick(event) }
            container.onPointerMove = { [weak self] event in self?.pointerMoved(event) }
            container.onPageStep = { [weak self] forward in self?.handlePageStep(forward) }
            container.onPan = { [weak self] dx, dy in self?.pan(dx: dx, dy: dy) }
            container.onContextMenu = { [weak self] _ in self?.contextMenuController.makeMenu() }

            strip.autoresizingMask = []
            strip.onClick = { [weak self] event in self?.handleClick(event) }
            strip.onPointerMove = { [weak self] event in self?.pointerMoved(event) }
            strip.onPageStep = { [weak self] forward in self?.handlePageStep(forward) }
            strip.onPan = { [weak self] dx, dy in self?.pan(dx: dx, dy: dy) }
            strip.onContextMenu = { [weak self] _ in self?.contextMenuController.makeMenu() }
            container.addSubview(strip)

            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay
            scrollView.pageSwipeEnabled = false
            scrollView.pageWheelEnabled = false
            scrollView.documentView = container

            scrollView.onZoomChanged = { [weak self] value in
                self?.session.setZoom(value)
                self?.syncPanState()
            }
            scrollView.onPageStep = { [weak self] forward in
                self?.handlePageStep(forward)
            }
            scrollView.onPointerMove = { [weak self] event in
                self?.pointerMoved(event)
            }
            scrollView.onPointerExit = { [weak self] in
                self?.session.chrome.pointerExited()
            }
            scrollView.onSmartZoom = { [weak self] event in
                self?.handleSmartZoom(event)
            }
            scrollView.onContextMenu = { [weak self] _ in self?.contextMenuController.makeMenu() }

            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )

            session.bridge.attach(self)
        }

        func update(pages: [PageSlot], seek: WebtoonSeekRequest, viewport: CGSize) {
            guard installed else { return }
            guard viewport.width > 1, viewport.height > 1 else { return }

            // Scrolling changes `currentPageIndex` on every other page, which
            // re-runs this update. Keep those passes free of layout work.
            isUpdating = true

            let pagesChanged = pages != currentPages || pageViews.count != pages.count
            if pagesChanged {
                rebuildPageViews(count: pages.count, releasing: currentPages.map(\.source))
                currentPages = pages
                currentSources = pages.map(\.source)
                didInitialScroll = false
            }

            let width = max(viewport.width, 1)
            let widthChanged = abs(width - lastWidth) > 0.5
            let needsLayout = pagesChanged || widthChanged || stripLayout.heights.count != pages.count

            var anchor: (page: Int, offset: CGFloat)?
            var previousStripWidth: CGFloat = 0

            if needsLayout {
                if widthChanged, didInitialScroll {
                    anchor = currentAnchor()
                    previousStripWidth = stripLayout.stripWidth
                }
                stripLayout = WebtoonStripLayout.make(pages: pages, viewportWidth: width)
                lastWidth = width
                applyLayout(viewportHeight: viewport.height)
            } else if abs(viewport.height - lastViewportHeight) > 0.5 {
                lastViewportHeight = viewport.height
                container.frame.size.height = max(viewport.height, stripLayout.totalHeight)
            }

            if !didInitialScroll {
                didInitialScroll = true
                let page = min(max(session.currentPageIndex, 0), max(0, pages.count - 1))
                scrollTo(page: page, extra: 0)
            } else if let anchor, previousStripWidth > 0 {
                let ratio = stripLayout.stripWidth / previousStripWidth
                scrollTo(page: anchor.page, extra: anchor.offset * ratio)
            }

            var didSeek = false
            if seek.id != lastSeekID {
                lastSeekID = seek.id
                scrollTo(page: seek.page, extra: 0)
                didSeek = true
            }

            isUpdating = false

            if needsLayout || didSeek {
                Task { @MainActor [weak self] in
                    guard let self, self.installed else { return }
                    self.updateVisiblePage(force: true)
                }
            }
        }

        // MARK: - Layout helpers

        private func applyLayout(viewportHeight: CGFloat) {
            guard let scrollView else { return }
            lastViewportHeight = viewportHeight
            container.frame = CGRect(
                x: 0,
                y: 0,
                width: lastWidth,
                height: max(viewportHeight, stripLayout.totalHeight)
            )
            strip.frame = CGRect(
                x: (lastWidth - stripLayout.stripWidth) / 2,
                y: 0,
                width: stripLayout.stripWidth,
                height: max(stripLayout.totalHeight, 1)
            )

            for (index, view) in pageViews.enumerated() {
                if let view {
                    applyFrame(to: view, at: index)
                }
            }

            scrollView.layoutSubtreeIfNeeded()
            syncPanState()
        }

        private func applyFrame(to view: PageContentView, at index: Int) {
            guard stripLayout.tops.indices.contains(index) else { return }
            view.frame = CGRect(
                x: 0,
                y: stripLayout.tops[index],
                width: stripLayout.stripWidth,
                height: stripLayout.heights[index]
            )
        }

        private func makePageView() -> PageContentView {
            let view = PageContentView()
            view.onClick = { [weak self] event in self?.handleClick(event) }
            view.onPointerMove = { [weak self] event in self?.pointerMoved(event) }
            view.onPageStep = { [weak self] forward in self?.handlePageStep(forward) }
            view.onPan = { [weak self] dx, dy in self?.pan(dx: dx, dy: dy) }
            view.onContextMenu = { [weak self] _ in self?.contextMenuController.makeMenu() }
            view.isPanEnabled = scrollView?.canPan ?? false
            return view
        }

        private func pageView(at index: Int) -> PageContentView? {
            guard pageViews.indices.contains(index) else { return nil }
            if let view = pageViews[index] { return view }

            let view = makePageView()
            pageViews[index] = view
            strip.addSubview(view)
            applyFrame(to: view, at: index)
            return view
        }

        private func rebuildPageViews(count: Int, releasing sources: [PageSource]) {
            generation += 1
            for task in loadTasks.values { task.cancel() }
            loadTasks.removeAll()
            let requests = releaseRequests(for: Array(loadTokens.keys), sources: sources)
            loadTokens.removeAll()
            if !requests.isEmpty {
                Task { await ImagePrefetcher.shared.cancelLoads(requests) }
            }

            for view in pageViews.compactMap({ $0 }) {
                view.removeFromSuperview()
            }
            pageViews = Array(repeating: nil, count: count)
            stripLayout = .empty
            lastLoadedWindow = nil
            lastRetentionWindow = nil
            lastVisiblePage = -1
        }

        /// Page sources paired with the token that owns their decode, so a
        /// cancellation arriving late cannot stop a newer load of the same page.
        private func releaseRequests(for indices: [Int], sources: [PageSource]) -> [PageSource: UUID] {
            var requests: [PageSource: UUID] = [:]
            for index in indices where sources.indices.contains(index) {
                if let token = loadTokens[index] {
                    requests[sources[index]] = token
                }
            }
            return requests
        }

        private func currentAnchor() -> (page: Int, offset: CGFloat)? {
            guard let scrollView, !stripLayout.tops.isEmpty else { return nil }
            let visible = scrollView.documentVisibleRect
            let page = stripLayout.pageIndex(containingY: visible.midY)
            let offset = max(0, visible.minY - stripLayout.tops[page])
            return (page, offset)
        }

        private func scrollTo(page: Int, extra: CGFloat) {
            guard let scrollView, !stripLayout.tops.isEmpty else { return }
            let index = min(max(page, 0), stripLayout.tops.count - 1)
            let y = stripLayout.tops[index] + extra
            scrollView.layoutSubtreeIfNeeded()
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        // MARK: - Visible tracking

        @objc private func boundsDidChange(_ notification: Notification) {
            guard installed, !isUpdating else { return }
            updateVisiblePage(force: false)
        }

        private func updateVisiblePage(force: Bool) {
            guard let scrollView, !stripLayout.tops.isEmpty else { return }
            let page = stripLayout.pageIndex(containingY: scrollView.documentVisibleRect.midY)
            if page != lastVisiblePage || force {
                lastVisiblePage = page
                session.noteVisiblePage(page)
                maintainLoadWindow(center: page)
            }
        }

        private func maintainLoadWindow(center: Int) {
            let pageCount = pageViews.count
            guard
                let window = PageWindow(
                    center: center,
                    before: Self.loadWindowBefore,
                    after: Self.loadWindowAfter,
                    pageCount: pageCount
                )
            else { return }
            guard window != lastLoadedWindow else { return }
            lastLoadedWindow = window

            for index in window.range {
                loadPage(index)
            }
            prefetch(window: window)

            let stale = loadTasks.keys.filter { !window.contains($0) }
            let requests = releaseRequests(for: stale, sources: currentSources)
            for index in stale {
                loadTasks[index]?.cancel()
                loadTasks[index] = nil
                loadTokens[index] = nil
                pageViews[index]?.cancelLoading()
            }
            if !requests.isEmpty {
                Task { await ImagePrefetcher.shared.cancelLoads(requests) }
            }

            guard
                let retention = PageWindow(
                    center: center,
                    before: Self.retentionWindowBefore,
                    after: Self.retentionWindowAfter,
                    pageCount: pageCount
                )
            else { return }

            if let previous = lastRetentionWindow {
                for index in previous.indices(excluding: retention) {
                    pageViews[index]?.clearImage()
                }
            } else {
                for (index, view) in pageViews.enumerated() where !retention.contains(index) {
                    view?.clearImage()
                }
            }
            lastRetentionWindow = retention
        }

        private func prefetch(window: PageWindow) {
            prefetchTask?.cancel()
            let sources = window.range.compactMap { index -> PageSource? in
                session.pageSlots.indices.contains(index) ? session.pageSlots[index].source : nil
            }
            prefetchTask = Task {
                guard !Task.isCancelled else { return }
                await ImagePrefetcher.shared.updatePrefetchWindow(sources)
            }
        }

        private func loadPage(_ index: Int) {
            guard currentSources.indices.contains(index),
                session.pageSlots.indices.contains(index),
                let view = pageView(at: index)
            else { return }
            if view.hasImage || view.isLoading { return }

            let slot = session.pageSlots[index]
            view.beginLoading(for: slot.source)
            let generation = generation
            let token = UUID()
            loadTokens[index] = token
            let task = Task { [weak self, weak view] in
                guard !Task.isCancelled else { return }
                do {
                    let image = try await ImagePrefetcher.shared.image(
                        for: slot.source,
                        request: token
                    )
                    guard !Task.isCancelled else { return }
                    guard let self, self.generation == generation else { return }
                    guard let view,
                        self.pageViews.indices.contains(index),
                        self.pageViews[index] === view
                    else { return }
                    view.show(image: image)
                } catch {
                    guard !Task.isCancelled else { return }
                    guard let self, self.generation == generation else { return }
                    guard let view,
                        self.pageViews.indices.contains(index),
                        self.pageViews[index] === view
                    else { return }
                    view.showError()
                }
            }
            loadTasks[index] = task
        }

        // MARK: - Interaction

        private func handleClick(_ event: NSEvent) {
            guard !session.isLoadingChapter,
                !session.isHelpVisible,
                !session.isPageEntryVisible
            else { return }
            scrollView?.window?.makeFirstResponder(scrollView)
            guard let scrollView else { return }

            let point = scrollView.convert(event.locationInWindow, from: nil)
            let action = ReaderInteraction.clickAction(
                x: point.x,
                width: scrollView.bounds.width,
                direction: session.direction
            )

            switch action {
            case .previous:
                guard event.clickCount == 1 else { return }
                session.previous()
            case .next:
                guard event.clickCount == 1 else { return }
                session.next()
            case .none:
                if event.clickCount >= 2 {
                    handleSmartZoom(event)
                }
            }
        }

        private func pointerMoved(_ event: NSEvent) {
            guard let scrollView else { return }
            let width = scrollView.bounds.width
            let height = scrollView.bounds.height
            guard width > 1, height > 1 else { return }

            let point = scrollView.convert(event.locationInWindow, from: nil)
            session.chrome.updatePointer(xFromLeft: point.x)

            // Keep the normal arrow over the floating chrome; show the
            // navigation chevron only over the actual page.
            if session.chrome.isSideVisible && point.x <= ReaderSidebarLayout.hitWidth {
                ReaderCursors.apply(.arrow)
            } else {
                let zone = ReaderInteraction.sideZone(x: point.x, width: width)
                ReaderCursors.apply(
                    ReaderCursors.style(for: zone, canPan: scrollView.canPan)
                )
            }
        }

        private func handleSmartZoom(_ event: NSEvent) {
            guard let scrollView else { return }
            let point = scrollView.contentView.convert(event.locationInWindow, from: nil)
            let target: CGFloat = scrollView.magnification > 1.02 ? 1.0 : 2.5
            scrollView.zoom(to: target, at: point, animated: true)
        }

        private func handlePageStep(_ forward: Bool) {
            guard !session.isLoadingChapter,
                !session.isHelpVisible,
                !session.isPageEntryVisible
            else { return }
            scrollView?.window?.makeFirstResponder(scrollView)
            if forward {
                session.next()
            } else {
                session.previous()
            }
        }

        private func pan(dx: CGFloat, dy: CGFloat) {
            guard let scrollView, let documentView = scrollView.documentView else { return }
            let visible = scrollView.documentVisibleRect
            let maxX = max(0, documentView.bounds.width - visible.width)
            let maxY = max(0, documentView.bounds.height - visible.height)

            var origin = visible.origin
            origin.x = min(max(origin.x - dx, 0), maxX)
            origin.y = min(max(origin.y - dy, 0), maxY)
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func syncPanState() {
            guard let scrollView else { return }
            let canPan = scrollView.canPan
            container.isPanEnabled = canPan
            strip.isPanEnabled = canPan
            for view in pageViews.compactMap({ $0 }) {
                view.isPanEnabled = canPan
            }
        }

        // MARK: - ReaderCanvasControlling

        func resetZoom(animated: Bool) {
            session.setZoom(1)
            scrollView?.resetZoom(animated: animated)
        }

        func zoomIn() {
            scrollView?.zoomStep(by: 1.4)
        }

        func zoomOut() {
            scrollView?.zoomStep(by: 1 / 1.4)
        }

        func scrollScreen(forward: Bool) -> Bool {
            guard let scrollView else { return false }
            let visible = scrollView.documentVisibleRect
            let documentHeight = scrollView.documentView?.bounds.height ?? 0
            let maxY = max(0, documentHeight - visible.height)

            if forward {
                guard visible.minY < maxY - 1 else { return false }
                let target = min(maxY, visible.minY + visible.height * 0.86)
                scroll(toY: target, scrollView: scrollView)
                return true
            }

            guard visible.minY > 1 else { return false }
            let target = max(0, visible.minY - visible.height * 0.86)
            scroll(toY: target, scrollView: scrollView)
            return true
        }

        private func scroll(toY y: CGFloat, scrollView: ReaderScrollView) {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            updateVisiblePage(force: true)
        }

        func focusCanvas() {
            guard let scrollView else { return }
            scrollView.window?.makeFirstResponder(scrollView)
        }

        // MARK: - Teardown

        func teardown() {
            installed = false
            NotificationCenter.default.removeObserver(self)
            for task in loadTasks.values { task.cancel() }
            loadTasks.removeAll()
            prefetchTask?.cancel()
            prefetchTask = nil
            let requests = releaseRequests(for: Array(loadTokens.keys), sources: currentSources)
            loadTokens.removeAll()
            if !requests.isEmpty {
                Task { await ImagePrefetcher.shared.cancelLoads(requests) }
            }
            scrollView?.cancelAnimations()
            session.bridge.detach(self)
            scrollView = nil
        }
    }
}
