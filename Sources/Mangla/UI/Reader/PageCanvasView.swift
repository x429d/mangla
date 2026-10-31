import AppKit
import QuartzCore
import SwiftUI

/// Single page / double page reader, backed by a native `NSScrollView` with
/// AppKit magnification (no SwiftUI `.scaleEffect`).
struct PageCanvasRepresentable: NSViewRepresentable {
    let session: ReadingSession
    let slots: [PageSlot]
    let fitMode: FitMode
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
        context.coordinator.update(
            slots: slots,
            fitMode: fitMode,
            viewport: viewport
        )
    }

    static func dismantleNSView(_ scrollView: ReaderScrollView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator: NSObject, ReaderCanvasControlling {
        let session: ReadingSession

        private(set) var scrollView: ReaderScrollView?
        private let container = CanvasSurfaceView()
        private let surface = CanvasSurfaceView()
        private var pageViews: [PageContentView] = []
        private var loadTasks: [Int: Task<Void, Never>] = [:]
        private var prefetchTask: Task<Void, Never>?
        private lazy var contextMenuController = ReaderContextMenuController(session: session)

        private var currentSources: [PageSource] = []
        private var currentSlots: [PageSlot] = []
        private var currentQuality: PageRenderQuality = .standard
        private var currentFit: FitMode?
        private var lastRenderedPageIndex: Int?
        private var generation = 0
        private var installed = false

        /// PDF pages are rasterized on demand, so a strong zoom asks for a
        /// sharper render of the visible page.
        private var renderQuality: PageRenderQuality {
            session.zoom >= 2.2 ? .high : .standard
        }

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

            surface.autoresizingMask = []
            surface.wantsLayer = true
            surface.onClick = { [weak self] event in self?.handleClick(event) }
            surface.onPointerMove = { [weak self] event in self?.pointerMoved(event) }
            surface.onPageStep = { [weak self] forward in self?.handlePageStep(forward) }
            surface.onPan = { [weak self] dx, dy in self?.pan(dx: dx, dy: dy) }
            surface.onContextMenu = { [weak self] _ in self?.contextMenuController.makeMenu() }
            container.addSubview(surface)

            scrollView.documentView = container
            scrollView.onZoomChanged = { [weak self] value in
                self?.session.setZoom(value)
                self?.refreshDetailLevel()
                self?.syncPanState()
            }
            scrollView.onHorizontalSwipe = { [weak self] delta in
                self?.handleSwipe(delta)
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
            scrollView.pageSwipeEnabled = true

            session.bridge.attach(self)
        }

        func update(slots: [PageSlot], fitMode: FitMode, viewport: CGSize) {
            guard let scrollView, installed else { return }
            guard viewport.width > 1, viewport.height > 1 else { return }

            let sources = slots.map(\.source)
            let slotsChanged = sources != currentSources
            let fitChanged = fitMode != currentFit
            let quality = renderQuality
            let qualityChanged = !slotsChanged && quality != currentQuality

            let newPageIndex = session.currentPageIndex
            let movingForward: Bool?
            if slotsChanged, !currentSources.isEmpty,
                let last = lastRenderedPageIndex, newPageIndex != last
            {
                movingForward = newPageIndex > last
            } else {
                movingForward = nil
            }

            if slotsChanged {
                if let movingForward {
                    scrollView.resetZoomWithoutNotification()
                    scrollToTop()
                    animatePageTurn(movingForward: movingForward)
                }
                rebuildPageViews(for: slots)
            }

            let layout = PageLayoutCalculator.layout(slots: slots, fit: fitMode, viewport: viewport)
            container.frame = CGRect(origin: .zero, size: layout.containerSize)
            surface.frame = layout.surfaceRect

            for (index, pageView) in pageViews.enumerated() where layout.pageRects.indices.contains(index) {
                pageView.frame = layout.pageRects[index]
            }

            if fitChanged, let scrollView = self.scrollView {
                scrollView.resetZoomWithoutNotification()
            }

            scrollView.pageSwipeEnabled = layout.containerSize.width <= viewport.width + 1
            scrollView.pageWheelEnabled = layout.containerSize.height <= viewport.height + 1

            if slotsChanged {
                scrollToTop()
                loadImages(for: slots, quality: quality)
            } else if qualityChanged {
                upgradeRenderedPages(for: slots, quality: quality)
            } else if fitChanged {
                scrollToTop()
            }

            // Clip-view bounds are only reliable after the layout pass, so pan
            // availability is refreshed at the end of the update.
            scrollView.layoutSubtreeIfNeeded()
            syncPanState()

            currentSources = sources
            currentSlots = slots
            currentQuality = quality
            currentFit = fitMode
            lastRenderedPageIndex = newPageIndex

            prefetch()
        }

        // MARK: - Page views

        private func rebuildPageViews(for slots: [PageSlot]) {
            generation += 1
            for task in loadTasks.values { task.cancel() }
            loadTasks.removeAll()

            for view in pageViews {
                view.removeFromSuperview()
            }
            pageViews = slots.map { _ in
                let view = PageContentView()
                view.onClick = { [weak self] event in self?.handleClick(event) }
                view.onPointerMove = { [weak self] event in self?.pointerMoved(event) }
                view.onPageStep = { [weak self] forward in self?.handlePageStep(forward) }
                view.onPan = { [weak self] dx, dy in self?.pan(dx: dx, dy: dy) }
                view.onContextMenu = { [weak self] _ in self?.contextMenuController.makeMenu() }
                view.isPanEnabled = scrollView?.canPan ?? false
                return view
            }
            for view in pageViews {
                surface.addSubview(view)
            }
        }

        private func loadImages(for slots: [PageSlot], quality: PageRenderQuality) {
            let generation = generation
            for (index, slot) in slots.enumerated() where pageViews.indices.contains(index) {
                let view = pageViews[index]
                if view.source == slot.source, view.hasImage || view.isLoading {
                    continue
                }
                view.beginLoading(for: slot.source)

                let task = Task { [weak self, weak view] in
                    do {
                        let image = try await ImagePrefetcher.shared.image(
                            for: slot.source,
                            quality: quality
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
        }

        /// Re-renders already visible PDF pages at the sharper detail level.
        /// Image files and archive pages are decoded at native size and are
        /// left untouched.
        private func upgradeRenderedPages(for slots: [PageSlot], quality: PageRenderQuality) {
            guard quality == .high else { return }
            let generation = generation

            for (index, slot) in slots.enumerated()
            where slot.source.isPDF && pageViews.indices.contains(index) {
                let view = pageViews[index]
                guard view.hasImage, !view.isLoading else { continue }
                view.beginUpgrade()

                let task = Task { [weak self, weak view] in
                    do {
                        let image = try await ImagePrefetcher.shared.image(
                            for: slot.source,
                            quality: quality
                        )
                        guard !Task.isCancelled else { return }
                        guard let self, self.generation == generation else { return }
                        guard let view,
                            self.pageViews.indices.contains(index),
                            self.pageViews[index] === view
                        else { return }
                        view.show(image: image)
                    } catch {
                        guard let view else { return }
                        view.cancelUpgrade()
                    }
                }
                loadTasks[index]?.cancel()
                loadTasks[index] = task
            }
        }

        /// Called from the magnification observer: a strong zoom asks the
        /// visible PDF pages for a sharper render. Image and archive pages are
        /// already at native resolution.
        private func refreshDetailLevel() {
            guard installed else { return }
            let quality = renderQuality
            guard quality != currentQuality else { return }
            currentQuality = quality
            guard quality == .high else { return }
            upgradeRenderedPages(for: currentSlots, quality: quality)
        }

        private func prefetch() {
            prefetchTask?.cancel()
            let sources = session.prefetchSources
            prefetchTask = Task {
                guard !Task.isCancelled else { return }
                await ImagePrefetcher.shared.updatePrefetchWindow(sources)
            }
        }

        // MARK: - Scrolling

        private func scrollToTop() {
            guard let scrollView else { return }
            scrollView.layoutSubtreeIfNeeded()
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
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

        private func animatePageTurn(movingForward: Bool) {
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            guard let layer = surface.layer else { return }

            let fromRight = ReaderInteraction.comesFromRight(
                movingForward: movingForward,
                direction: session.direction
            )
            let transition = CATransition()
            transition.type = .push
            transition.subtype = fromRight ? .fromRight : .fromLeft
            transition.duration = 0.16
            transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(transition, forKey: "mangla.pageTurn")
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

        private func handleSwipe(_ delta: CGFloat) {
            guard scrollView?.pageSwipeEnabled == true,
                !session.isLoadingChapter,
                !session.isHelpVisible,
                !session.isPageEntryVisible
            else { return }
            let forward = session.direction == .rtl ? delta > 0 : delta < 0
            if forward {
                session.next()
            } else {
                session.previous()
            }
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
            let surfaces: [CanvasSurfaceView] = [container, surface] + pageViews
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
            // While zoomed, stop at the edge instead of flipping the page and
            // resetting the magnification under the reader's hands.
            let zoomed = scrollView.magnification > 1.001

            if forward {
                guard visible.minY < maxY - 1 else { return zoomed }
                let target = min(maxY, visible.minY + visible.height * 0.86)
                scroll(toY: target, scrollView: scrollView)
                return true
            }

            guard visible.minY > 1 else { return zoomed }
            let target = max(0, visible.minY - visible.height * 0.86)
            scroll(toY: target, scrollView: scrollView)
            return true
        }

        private func scroll(toY y: CGFloat, scrollView: ReaderScrollView) {
            scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func focusCanvas() {
            guard let scrollView else { return }
            scrollView.window?.makeFirstResponder(scrollView)
        }

        // MARK: - Teardown

        func teardown() {
            installed = false
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
