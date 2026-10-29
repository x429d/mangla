import AppKit
import QuartzCore

// MARK: - Base views

/// Flipped surface that forwards clicks and mouse movement to the reader.
@MainActor
class CanvasSurfaceView: NSView {
    var onClick: ((NSEvent) -> Void)?
    var onActivity: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?(event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        onActivity?()
    }

    override func mouseEntered(with event: NSEvent) {
        onActivity?()
    }
}

@MainActor
final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A page cell: dark placeholder, spinner, optional error text.
@MainActor
final class PageContentView: CanvasSurfaceView {
    private let imageView = PassthroughImageView()
    private let messageLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()

    private(set) var url: URL?
    private(set) var hasImage = false
    private(set) var isLoading = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.074, green: 0.078, blue: 0.090, alpha: 1).cgColor
        layer?.borderWidth = 0

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.animates = false
        addSubview(imageView)

        messageLabel.isHidden = true
        messageLabel.alignment = .center
        messageLabel.font = .systemFont(ofSize: 11, weight: .medium)
        messageLabel.textColor = NSColor.white.withAlphaComponent(0.55)
        messageLabel.maximumNumberOfLines = 3
        messageLabel.lineBreakMode = .byTruncatingMiddle
        messageLabel.usesSingleLineMode = false
        addSubview(messageLabel)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.appearance = NSAppearance(named: .darkAqua)
        addSubview(spinner)
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
        let width = max(60, min(bounds.width - 36, 460))
        messageLabel.frame = NSRect(
            x: (bounds.width - width) / 2,
            y: max(8, (bounds.height - 56) / 2),
            width: width,
            height: 56
        )
        spinner.frame = NSRect(
            x: (bounds.width - 16) / 2,
            y: (bounds.height - 16) / 2,
            width: 16,
            height: 16
        )
    }

    func beginLoading(for url: URL) {
        self.url = url
        imageView.image = nil
        hasImage = false
        isLoading = true
        messageLabel.isHidden = true
        spinner.isHidden = false
        spinner.startAnimation(nil)
    }

    func show(image: CGImage) {
        hasImage = true
        isLoading = false
        messageLabel.isHidden = true
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        imageView.image = NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    func showError() {
        imageView.image = nil
        hasImage = false
        isLoading = false
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        messageLabel.stringValue = "Не удалось открыть страницу\n\(url?.lastPathComponent ?? "")"
        messageLabel.isHidden = false
    }

    func clearImage() {
        imageView.image = nil
        hasImage = false
        isLoading = false
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        messageLabel.isHidden = true
    }

    func stopLoading() {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
    }
}

// MARK: - Smooth zoom animation (display-link driven)

@MainActor
final class ZoomAnimator: NSObject {
    var onTick: ((CGFloat) -> Void)?

    private var link: CADisplayLink?
    private weak var scrollView: NSScrollView?
    private var startTime: CFTimeInterval = 0
    private var duration: CFTimeInterval = 0.3
    private var from: CGFloat = 1
    private var to: CGFloat = 1
    private var point: NSPoint = .zero

    func animate(
        scrollView: NSScrollView,
        to target: CGFloat,
        at point: NSPoint,
        duration: CFTimeInterval = 0.3
    ) {
        self.scrollView = scrollView
        self.from = scrollView.magnification
        self.to = target
        self.point = point
        self.duration = max(0.05, duration)
        self.startTime = CACurrentMediaTime()

        if link == nil {
            let link = scrollView.displayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let scrollView else {
            invalidate()
            return
        }
        let progress = min(1, max(0, (CACurrentMediaTime() - startTime) / duration))
        let eased = 1 - pow(1 - progress, 3)
        let value = from + (to - from) * CGFloat(eased)
        scrollView.setMagnification(value, centeredAt: point)
        onTick?(value)
        if progress >= 1 {
            invalidate()
        }
    }

    func invalidate() {
        link?.invalidate()
        link = nil
        scrollView = nil
    }
}

// MARK: - Reader scroll view

@MainActor
final class ReaderScrollView: NSScrollView {
    var onZoomChanged: ((CGFloat) -> Void)?
    var onHorizontalSwipe: ((CGFloat) -> Void)?
    var onMouseActivity: (() -> Void)?
    var onScrollActivity: (() -> Void)?
    var onSmartZoom: ((NSEvent) -> Void)?
    var pageSwipeEnabled = false

    private var swipeAccumulator: CGFloat = 0
    private var swipeFired = false
    private var swipeResetTask: Task<Void, Never>?
    private lazy var zoomAnimator: ZoomAnimator = {
        let animator = ZoomAnimator()
        animator.onTick = { [weak self] value in
            self?.onZoomChanged?(value)
        }
        return animator
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        drawsBackground = true
        backgroundColor = NSColor(calibratedRed: 0.020, green: 0.020, blue: 0.024, alpha: 1)
        borderType = .noBorder
        hasVerticalScroller = false
        hasHorizontalScroller = false
        scrollerStyle = .overlay
        autohidesScrollers = true
        verticalScrollElasticity = .automatic
        horizontalScrollElasticity = .automatic
        allowsMagnification = true
        minMagnification = 1
        maxMagnification = 5
        magnification = 1
        contentView.postsBoundsChangedNotifications = true
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseActivity?()
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseActivity?()
    }

    // Native pinch-to-zoom, anchored at the cursor.
    override func magnify(with event: NSEvent) {
        onMouseActivity?()
        let factor = 1 + event.magnification
        guard factor.isFinite, factor > 0 else { return }
        let target = min(max(magnification * factor, minMagnification), maxMagnification)
        let point = contentView.convert(event.locationInWindow, from: nil)
        zoomAnimator.invalidate()
        setMagnification(target, centeredAt: point)
        onZoomChanged?(magnification)
    }

    override func smartMagnify(with event: NSEvent) {
        onSmartZoom?(event)
    }

    // Two-finger horizontal swipe flips pages when zoomed out.
    override func scrollWheel(with event: NSEvent) {
        onScrollActivity?()
        let atBaseZoom = magnification <= 1.001

        guard pageSwipeEnabled, atBaseZoom, event.hasPreciseScrollingDeltas else {
            super.scrollWheel(with: event)
            return
        }

        if event.momentumPhase != [] {
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                return
            }
            super.scrollWheel(with: event)
            return
        }

        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.15 else {
            super.scrollWheel(with: event)
            return
        }

        if event.phase == .began {
            swipeAccumulator = 0
            swipeFired = false
        }
        if event.phase == .ended || event.phase == .cancelled {
            swipeAccumulator = 0
            swipeFired = false
            return
        }

        swipeAccumulator += event.scrollingDeltaX

        if !swipeFired, abs(swipeAccumulator) >= 58 {
            swipeFired = true
            onHorizontalSwipe?(swipeAccumulator)
            scheduleSwipeReset()
        }
    }

    private func scheduleSwipeReset() {
        swipeResetTask?.cancel()
        swipeResetTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            self?.swipeAccumulator = 0
            self?.swipeFired = false
        }
    }

    // MARK: Zoom control

    func zoom(to target: CGFloat, at point: NSPoint, animated: Bool) {
        let clamped = min(max(target, minMagnification), maxMagnification)
        guard animated else {
            zoomAnimator.invalidate()
            setMagnification(clamped, centeredAt: point)
            onZoomChanged?(clamped)
            return
        }
        zoomAnimator.animate(scrollView: self, to: clamped, at: point, duration: 0.3)
    }

    func zoomStep(by factor: CGFloat) {
        let target = magnification * factor
        zoom(to: target, at: viewportCenterPoint, animated: true)
    }

    func resetZoom(animated: Bool) {
        zoom(to: 1, at: viewportCenterPoint, animated: animated)
    }

    /// Used while re-laying out after a fit-mode change. The session already
    /// holds zoom == 1, so publishing again here would mutate state during a
    /// SwiftUI update.
    func resetZoomWithoutNotification() {
        zoomAnimator.invalidate()
        setMagnification(1, centeredAt: viewportCenterPoint)
    }

    var viewportCenterPoint: NSPoint {
        NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
    }

    func cancelAnimations() {
        zoomAnimator.invalidate()
    }
}
