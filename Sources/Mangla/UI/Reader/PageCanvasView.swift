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

        private var currentURLs: [URL] = []
        private var currentFit: FitMode?
        private var lastRenderedPageIndex: Int?
        private var lastViewport: CGSize = .zero
        private var generation = 0
        private var installed = false

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

            surface.autoresizingMask = []
            surface.wantsLayer = true
            surface.onClick = { [weak self] event in self?.handleClick(event) }
            surface.onPointerMove = { [weak self] event in self?.pointerMoved(event) }
            container.addSubview(surface)

            scrollView.documentView = container
            scrollView.onZoomChanged = { [weak self] value in
                self?.session.setZoom(value)
            }
            scrollView.onHorizontalSwipe = { [weak self] delta in
                self?.handleSwipe(delta)
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
            scrollView.pageSwipeEnabled = true

            session.bridge.attach(self)
        }

        func update(slots: [PageSlot], fitMode: FitMode, viewport: CGSize) {
            guard let scrollView, installed else { return }
            guard viewport.width > 1, viewport.height > 1 else { return }

            let urls = slots.map(\.url)
            let slotsChanged = urls != currentURLs
            let fitChanged = fitMode != currentFit
            let viewportChanged = viewport != lastViewport

            let newPageIndex = session.currentPageIndex
            let movingForward: Bool?
            if slotsChanged, !currentURLs.isEmpty,
               let last = lastRenderedPageIndex, newPageIndex != last {
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

            if slotsChanged {
                scrollToTop()
                loadImages(for: slots)
            } else if fitChanged || viewportChanged {
                scrollToTop()
            }

            currentURLs = urls
            currentFit = fitMode
            lastViewport = viewport
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
                return view
            }
            for view in pageViews {
                surface.addSubview(view)
            }
        }

        private func loadImages(for slots: [PageSlot]) {
            let generation = generation
            for (index, slot) in slots.enumerated() where pageViews.indices.contains(index) {
                let view = pageViews[index]
                if view.url == slot.url, view.hasImage || view.isLoading {
                    continue
                }
                view.beginLoading(for: slot.url)

                let task = Task { [weak self, weak view] in
                    do {
                        let image = try await ImagePrefetcher.shared.image(for: slot.url)
                        guard !Task.isCancelled else { return }
                        guard let self, self.generation == generation else { return }
                        guard let view,
                              self.pageViews.indices.contains(index),
                              self.pageViews[index] === view else { return }
                        view.show(image: image)
                    } catch {
                        guard !Task.isCancelled else { return }
                        guard let self, self.generation == generation else { return }
                        guard let view,
                              self.pageViews.indices.contains(index),
                              self.pageViews[index] === view else { return }
                        view.showError()
                    }
                }
                loadTasks[index] = task
            }
        }

        private func prefetch() {
            let urls = session.prefetchURLs
            Task {
                await ImagePrefetcher.shared.updatePrefetchWindow(urls)
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
            let yFromTop = height - point.y
            session.chrome.updatePointer(yFromTop: yFromTop, height: height)

            // Keep the normal arrow over the floating HUD panels; show the
            // navigation chevron only over the actual page.
            let overTopBar = session.chrome.isTopVisible && yFromTop <= 34
            let bottomWidth = min(1000, max(0, width - 32))
            let bottomMinX = (width - bottomWidth) / 2
            let overBottomBar = session.chrome.isBottomVisible
                && yFromTop >= height - 70
                && point.x >= bottomMinX
                && point.x <= bottomMinX + bottomWidth

            if overTopBar || overBottomBar {
                ReaderCursors.apply(.middle)
            } else {
                let zone = ReaderInteraction.sideZone(x: point.x, width: width)
                ReaderCursors.apply(zone)
            }
        }

        private func handleSmartZoom(_ event: NSEvent) {
            guard let scrollView else { return }
            let point = scrollView.contentView.convert(event.locationInWindow, from: nil)
            let target: CGFloat = scrollView.magnification > 1.02 ? 1.0 : 2.5
            scrollView.zoom(to: target, at: point, animated: true)
        }

        private func handleSwipe(_ delta: CGFloat) {
            guard scrollView?.pageSwipeEnabled == true else { return }
            let forward = session.direction == .rtl ? delta > 0 : delta < 0
            if forward {
                session.next()
            } else {
                session.previous()
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

        func focusCanvas() {
            guard let scrollView else { return }
            scrollView.window?.makeFirstResponder(scrollView)
        }

        // MARK: - Teardown

        func teardown() {
            installed = false
            for task in loadTasks.values { task.cancel() }
            loadTasks.removeAll()
            scrollView?.cancelAnimations()
            session.bridge.detach(self)
            scrollView = nil
        }
    }
}
