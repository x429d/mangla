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
        let session: ReadingSession

        private(set) var scrollView: ReaderScrollView?
        private let container = CanvasSurfaceView()
        private let strip = CanvasSurfaceView()
        private var pageViews: [PageContentView] = []
        private var loadTasks: [Int: Task<Void, Never>] = [:]
        private var prefetchTask: Task<Void, Never>?
        private lazy var contextMenuController = ReaderContextMenuController(session: session)

        private var currentSources: [PageSource] = []
        private var pageHeights: [CGFloat] = []
        private var pageTops: [CGFloat] = []
        private var generation = 0
        private var installed = false
        private var lastWidth: CGFloat = 0
        private var lastSeekID = 0
        private var didInitialScroll = false
        private var lastVisiblePage = -1
        private var lastLoadedWindow: ClosedRange<Int>?

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
            guard installed, self.scrollView != nil else { return }
            guard viewport.width > 1, viewport.height > 1 else { return }

            let sources = pages.map(\.source)
            if sources != currentSources {
                rebuildPageViews(count: pages.count)
                currentSources = sources
                didInitialScroll = false
            }

            let widthChanged = abs(viewport.width - lastWidth) > 0.5
            let anchor = widthChanged && didInitialScroll ? currentAnchor() : nil
            let oldStripWidth = strip.frame.width

            let width = max(viewport.width, 1)
            let stripWidth = min(width, 1000)
            let heights = pages.map { page in
                max(160, stripWidth / max(page.aspectRatio, 0.05))
            }
            let totalHeight = heights.reduce(0, +)
            pageHeights = heights
            pageTops = []
            pageTops.reserveCapacity(heights.count)
            var top: CGFloat = 0
            for height in heights {
                pageTops.append(top)
                top += height
            }

            container.frame = CGRect(
                x: 0,
                y: 0,
                width: width,
                height: max(viewport.height, totalHeight)
            )
            strip.frame = CGRect(
                x: (width - stripWidth) / 2,
                y: 0,
                width: stripWidth,
                height: max(totalHeight, 1)
            )

            for (index, view) in pageViews.enumerated() where heights.indices.contains(index) {
                view.frame = CGRect(x: 0, y: pageTops[index], width: stripWidth, height: heights[index])
            }

            lastWidth = width
            scrollView?.layoutSubtreeIfNeeded()
            syncPanState()

            if !didInitialScroll {
                didInitialScroll = true
                let page = min(max(session.currentPageIndex, 0), max(0, pages.count - 1))
                scrollTo(page: page, extra: 0)
            } else if let anchor, oldStripWidth > 0 {
                let ratio = stripWidth / oldStripWidth
                scrollTo(page: anchor.page, extra: anchor.offset * ratio)
            }

            if seek.id != lastSeekID {
                lastSeekID = seek.id
                scrollTo(page: seek.page, extra: 0)
            }

            Task { @MainActor [weak self] in
                self?.updateVisiblePage(force: true)
            }
        }

        // MARK: - Layout helpers

        private func rebuildPageViews(count: Int) {
            generation += 1
            for task in loadTasks.values { task.cancel() }
            loadTasks.removeAll()
            for view in pageViews { view.removeFromSuperview() }
            pageViews = (0..<count).map { _ in
                let view = PageContentView()
                view.onClick = { [weak self] event in self?.handleClick(event) }
                view.onPointerMove = { [weak self] event in self?.pointerMoved(event) }
                view.onPageStep = { [weak self] forward in self?.handlePageStep(forward) }
                view.onPan = { [weak self] dx, dy in self?.pan(dx: dx, dy: dy) }
                view.onContextMenu = { [weak self] _ in self?.contextMenuController.makeMenu() }
                view.isPanEnabled = scrollView?.canPan ?? false
                return view
            }
            for view in pageViews { strip.addSubview(view) }
            lastLoadedWindow = nil
            lastVisiblePage = -1
        }

        private func currentAnchor() -> (page: Int, offset: CGFloat)? {
            guard let scrollView, !pageTops.isEmpty else { return nil }
            let page = visiblePageIndex(in: scrollView)
            let offset = max(0, scrollView.documentVisibleRect.minY - pageTops[page])
            return (page, offset)
        }

        private func scrollTo(page: Int, extra: CGFloat) {
            guard let scrollView, !pageTops.isEmpty else { return }
            let index = min(max(page, 0), pageTops.count - 1)
            let y = pageTops[index] + extra
            scrollView.layoutSubtreeIfNeeded()
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func visiblePageIndex(in scrollView: NSScrollView) -> Int {
            guard !pageTops.isEmpty else { return 0 }
            let center = scrollView.documentVisibleRect.midY
            var low = 0
            var high = pageTops.count - 1
            var result = 0
            while low <= high {
                let mid = (low + high) / 2
                if pageTops[mid] <= center {
                    result = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            return result
        }

        // MARK: - Visible tracking

        @objc private func boundsDidChange(_ notification: Notification) {
            guard installed else { return }
            updateVisiblePage(force: false)
        }

        private func updateVisiblePage(force: Bool) {
            guard let scrollView, !pageTops.isEmpty else { return }
            let page = visiblePageIndex(in: scrollView)
            if page != lastVisiblePage || force {
                lastVisiblePage = page
                session.noteVisiblePage(page)
                maintainLoadWindow(center: page)
            }
        }

        private func maintainLoadWindow(center: Int) {
            guard !pageViews.isEmpty else { return }
            let lower = max(0, center - 2)
            let upper = min(pageViews.count - 1, center + 4)
            guard lower <= upper else { return }
            let window = lower...upper

            if lastLoadedWindow != window {
                lastLoadedWindow = window
                for index in window {
                    loadPage(index)
                }
                prefetch(window: window)

                let outdated = loadTasks.keys.filter { $0 < lower - 6 || $0 > upper + 6 }
                for index in outdated {
                    loadTasks[index]?.cancel()
                    loadTasks[index] = nil
                }
                for (index, view) in pageViews.enumerated()
                where index < max(0, center - 8) || index > min(pageViews.count - 1, center + 8) {
                    if view.hasImage {
                        view.clearImage()
                    }
                }
            }
        }

        private func prefetch(window: ClosedRange<Int>) {
            prefetchTask?.cancel()
            let sources = window.compactMap { index -> PageSource? in
                session.pageSlots.indices.contains(index) ? session.pageSlots[index].source : nil
            }
            prefetchTask = Task {
                guard !Task.isCancelled else { return }
                await ImagePrefetcher.shared.updatePrefetchWindow(sources)
            }
        }

        private func loadPage(_ index: Int) {
            guard pageViews.indices.contains(index),
                session.pageSlots.indices.contains(index)
            else { return }
            let view = pageViews[index]
            let slot = session.pageSlots[index]
            if view.hasImage || view.isLoading { return }

            view.beginLoading(for: slot.source)
            let generation = generation
            let task = Task { [weak self, weak view] in
                do {
                    let image = try await ImagePrefetcher.shared.image(for: slot.source)
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
            let surfaces: [CanvasSurfaceView] = [container, strip] + pageViews
            for view in surfaces {
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
            scrollView?.cancelAnimations()
            session.bridge.detach(self)
            scrollView = nil
        }
    }
}
