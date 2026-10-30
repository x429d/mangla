import AppKit
import Observation
import SwiftUI

// MARK: - Canvas bridge

@MainActor
protocol ReaderCanvasControlling: AnyObject {
    func resetZoom(animated: Bool)
    func zoomIn()
    func zoomOut()
    func scrollScreen(forward: Bool) -> Bool
    func focusCanvas()
}

@MainActor
final class ReaderBridge {
    private weak var canvas: (any ReaderCanvasControlling)?

    var isAttached: Bool { canvas != nil }

    func attach(_ canvas: any ReaderCanvasControlling) {
        self.canvas = canvas
    }

    func detach(_ canvas: any ReaderCanvasControlling) {
        if (self.canvas as AnyObject?) === (canvas as AnyObject) {
            self.canvas = nil
        }
    }

    func resetZoom() { resetZoom(animated: true) }
    func resetZoom(animated: Bool) { canvas?.resetZoom(animated: animated) }
    func zoomIn() { canvas?.zoomIn() }
    func zoomOut() { canvas?.zoomOut() }
    /// Returns true when the canvas consumed the scroll; false means it is at
    /// an edge and the caller may turn the page instead.
    func scrollScreen(forward: Bool) -> Bool {
        canvas?.scrollScreen(forward: forward) ?? false
    }
    func focus() { canvas?.focusCanvas() }
}

// MARK: - Floating HUD state

@MainActor
@Observable
final class ReaderChromeState {
    /// The full-height sidebar is tied to the left screen edge.
    var isSideVisible = false

    @ObservationIgnored private var isSideHovered = false
    @ObservationIgnored private var pointerNearSide = false
    @ObservationIgnored private var sideHideTask: Task<Void, Never>?

    /// A narrow strip reveals the sidebar so it does not compete with the
    /// left page-turn click zone. Once open, the whole panel plus a margin
    /// keeps it alive.
    private let sideRevealZone: CGFloat = 8
    private let sideKeepAliveZone: CGFloat = 280
    private let hideDelay: Duration

    init(hideDelay: Duration = .milliseconds(420)) {
        self.hideDelay = hideDelay
    }

    /// Called from the canvas on every mouse move. `xFromLeft` is measured in
    /// view points from the very left edge.
    func updatePointer(xFromLeft: CGFloat) {
        let sideLimit = isSideVisible ? sideKeepAliveZone : sideRevealZone
        let nearSide = xFromLeft <= sideLimit
        guard nearSide != pointerNearSide else { return }

        pointerNearSide = nearSide
        if nearSide {
            revealSide()
        } else {
            scheduleSideHide()
        }
    }

    func pointerExited() {
        pointerNearSide = false
        scheduleSideHide()
    }

    func setSideHovered(_ hovering: Bool) {
        guard hovering != isSideHovered else { return }
        isSideHovered = hovering
        if hovering {
            revealSide()
        } else if !pointerNearSide {
            scheduleSideHide()
        }
    }

    func hideAll() {
        sideHideTask?.cancel()
        sideHideTask = nil
        pointerNearSide = false
        isSideHovered = false
        isSideVisible = false
    }

    private func revealSide() {
        sideHideTask?.cancel()
        sideHideTask = nil
        isSideVisible = true
    }

    private func scheduleSideHide() {
        sideHideTask?.cancel()
        let delay = hideDelay
        sideHideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            guard !self.pointerNearSide, !self.isSideHovered else { return }
            self.isSideVisible = false
        }
    }
}

// MARK: - Seek request

struct WebtoonSeekRequest: Equatable, Sendable {
    let id: Int
    let page: Int
}

// MARK: - Reading session

@MainActor
@Observable
final class ReadingSession {
    let id = UUID()

    @ObservationIgnored weak var model: AppModel?

    private(set) var manga: MangaItem
    private(set) var chapter: ChapterItem

    private var storedLayoutMode: LayoutMode
    private var storedFitMode: FitMode
    private var storedDirection: ReadingDirection

    private(set) var pageSlots: [PageSlot] = []
    private(set) var spreads: [ReaderSpread] = []
    private(set) var spreadIndex = 0
    private(set) var currentPageIndex = 0
    private(set) var isLoadingChapter = true

    var zoom: CGFloat = 1
    var toast: String?
    var seekRequest = WebtoonSeekRequest(id: 0, page: 0)

    // Control-layer overlays
    private(set) var isHelpVisible = false
    private(set) var isPageEntryVisible = false
    var pageEntryText = ""

    let bridge = ReaderBridge()
    let chrome = ReaderChromeState()

    @ObservationIgnored private var metadataTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    init(
        model: AppModel,
        manga: MangaItem,
        chapter: ChapterItem,
        startPage: Int? = nil
    ) {
        self.model = model
        self.manga = manga
        self.chapter = chapter
        self.storedLayoutMode = ReaderPreferences.layoutMode
        self.storedFitMode = ReaderPreferences.fitMode
        self.storedDirection = ReaderPreferences.direction

        let resumePage =
            startPage
            ?? model.progress[manga.id]?.chapters[chapter.id]?.pageIndex
            ?? 0
        begin(startPage: resumePage)
    }

    // MARK: Preferences

    var layoutMode: LayoutMode {
        get { storedLayoutMode }
        set {
            guard newValue != storedLayoutMode else { return }
            storedLayoutMode = newValue
            ReaderPreferences.layoutMode = newValue
            rebuildSpreads(anchorPage: currentPageIndex)
            zoom = 1
        }
    }

    var fitMode: FitMode {
        get { storedFitMode }
        set {
            guard newValue != storedFitMode else { return }
            storedFitMode = newValue
            ReaderPreferences.fitMode = newValue
            zoom = 1
        }
    }

    var direction: ReadingDirection {
        get { storedDirection }
        set {
            storedDirection = newValue
            ReaderPreferences.direction = newValue
        }
    }

    func toggleDirection() {
        guard storedLayoutMode != .webtoon else { return }
        direction = storedDirection == .rtl ? .ltr : .rtl
    }

    // MARK: Derived state

    var currentSpread: ReaderSpread? {
        guard spreads.indices.contains(spreadIndex) else { return nil }
        return spreads[spreadIndex]
    }

    var currentSlots: [PageSlot] {
        guard let spread = currentSpread else { return [] }
        return spread.pageIndices.compactMap { pageSlots.indices.contains($0) ? pageSlots[$0] : nil }
    }

    /// Slots in physical screen order (RTL reverses a spread).
    var currentDisplaySlots: [PageSlot] {
        storedDirection == .rtl ? currentSlots.reversed() : currentSlots
    }

    var totalPages: Int { pageSlots.count }

    var currentPageLabel: String {
        if layoutMode == .webtoon {
            guard totalPages > 0 else { return "0 / 0" }
            return "\(currentPageIndex + 1) / \(totalPages)"
        }
        guard let spread = currentSpread else { return "0 / \(totalPages)" }
        let pages = spread.pageIndices.map { $0 + 1 }.sorted()
        if pages.count == 2 {
            return "\(pages[0])–\(pages[1]) / \(totalPages)"
        }
        return "\(pages.first ?? 0) / \(totalPages)"
    }

    var progressFraction: Double {
        guard totalPages > 1 else { return totalPages == 1 ? 1 : 0 }
        return Double(currentPageIndex + 1) / Double(totalPages)
    }

    var title: String { manga.title }
    var chapterTitle: String { chapter.title }

    var prefetchURLs: [URL] {
        guard !pageSlots.isEmpty else { return [] }
        let anchor = currentPageIndex
        let lower = max(0, anchor - 2)
        let upper = min(pageSlots.count - 1, anchor + 4)
        guard lower <= upper else { return [] }
        return pageSlots[lower...upper].map(\.url)
    }

    // MARK: Loading

    private func begin(startPage: Int) {
        guard !started else { return }
        started = true
        loadMetadata(startPage: startPage)
    }

    private func loadMetadata(startPage: Int) {
        metadataTask?.cancel()
        isLoadingChapter = true
        let pages = chapter.pages
        let urls = pages.map(\.url)

        metadataTask = Task { [weak self] in
            let sizes = await MetadataProbe.shared.sizes(for: urls)
            guard !Task.isCancelled, let self else { return }
            let slots = pages.map { page -> PageSlot in
                PageSlot(
                    url: page.url,
                    pixelSize: sizes[page.url] ?? CGSize(width: 1000, height: 1500)
                )
            }
            self.pageSlots = slots
            self.rebuildSpreads(anchorPage: startPage)
            self.isLoadingChapter = false
            self.zoom = 1
            self.recordProgress(force: true)
        }
    }

    private func rebuildSpreads(anchorPage: Int) {
        spreads = SpreadBuilder.spreads(pages: pageSlots, mode: storedLayoutMode)
        guard !spreads.isEmpty else {
            spreadIndex = 0
            currentPageIndex = 0
            return
        }
        let anchor = min(max(anchorPage, 0), max(0, pageSlots.count - 1))
        if let index = spreads.firstIndex(where: { $0.pageIndices.contains(anchor) }) {
            spreadIndex = index
        } else {
            spreadIndex = min(spreadIndex, spreads.count - 1)
        }
        syncPageIndexToSpread()
    }

    private func syncPageIndexToSpread() {
        guard let spread = currentSpread else { return }
        currentPageIndex = spread.pageIndices.max() ?? 0
    }

    // MARK: Navigation

    /// Every explicit page switch starts from the standard zoom and from the
    /// top of the new page. Continuous webtoon scrolling does not call this.
    private func prepareForPageTurn() {
        zoom = 1
        bridge.resetZoom(animated: false)
    }

    func next() {
        switch storedLayoutMode {
        case .single, .spread:
            if spreadIndex + 1 < spreads.count {
                prepareForPageTurn()
                spreadIndex += 1
                syncPageIndexToSpread()
                recordProgress()
            } else {
                nextChapter()
            }
        case .webtoon:
            if currentPageIndex + 1 < pageSlots.count {
                seek(to: currentPageIndex + 1)
            } else {
                nextChapter()
            }
        }
    }

    func previous() {
        switch storedLayoutMode {
        case .single, .spread:
            if spreadIndex > 0 {
                prepareForPageTurn()
                spreadIndex -= 1
                syncPageIndexToSpread()
                recordProgress()
            } else {
                previousChapter()
            }
        case .webtoon:
            if currentPageIndex > 0 {
                seek(to: currentPageIndex - 1)
            } else {
                previousChapter()
            }
        }
    }

    func goToPage(_ page: Int) {
        guard !pageSlots.isEmpty else { return }
        let target = min(max(page, 0), pageSlots.count - 1)
        switch storedLayoutMode {
        case .single, .spread:
            prepareForPageTurn()
            if let index = spreads.firstIndex(where: { $0.pageIndices.contains(target) }) {
                spreadIndex = index
                syncPageIndexToSpread()
                recordProgress()
            }
        case .webtoon:
            seek(to: target)
        }
    }

    private func seek(to page: Int) {
        prepareForPageTurn()
        currentPageIndex = min(max(page, 0), max(0, pageSlots.count - 1))
        seekRequest = WebtoonSeekRequest(id: seekRequest.id + 1, page: currentPageIndex)
        recordProgress()
    }

    /// Called by the webtoon canvas while the user scrolls.
    func noteVisiblePage(_ index: Int) {
        guard !pageSlots.isEmpty else { return }
        let clamped = min(max(index, 0), pageSlots.count - 1)
        guard clamped != currentPageIndex else { return }
        currentPageIndex = clamped
        recordProgress()
    }

    func nextChapter() {
        guard let target = model?.nextReadingTarget(afterMangaID: manga.id, chapterID: chapter.id) else {
            showToast(t(.toastLastChapter))
            return
        }
        switchTo(manga: target.manga, chapter: target.chapter, startPage: 0)
    }

    func previousChapter() {
        guard let target = model?.previousReadingTarget(afterMangaID: manga.id, chapterID: chapter.id) else {
            showToast(t(.toastFirstChapter))
            return
        }
        switchTo(
            manga: target.manga,
            chapter: target.chapter,
            startPage: max(0, target.chapter.pageCount - 1)
        )
    }

    private func switchTo(manga newManga: MangaItem, chapter newChapter: ChapterItem, startPage: Int) {
        recordProgress(force: true)
        let previousMangaID = manga.id
        manga = newManga
        chapter = newChapter
        pageSlots = []
        spreads = []
        spreadIndex = 0
        currentPageIndex = 0
        zoom = 1
        isLoadingChapter = true
        // A seek request from the previous chapter must not move the new
        // webtoon canvas to an unrelated page during its initial layout.
        seekRequest = WebtoonSeekRequest(id: 0, page: 0)
        loadMetadata(startPage: startPage)

        let subtitle =
            newManga.id == previousMangaID
            ? newChapter.title
            : "\(newManga.title) · \(newChapter.title)"
        showToast(tf(.toastNextUp, subtitle))
        model?.noteOpened(manga: newManga, chapter: newChapter)
    }

    // MARK: Zoom

    func setZoom(_ value: CGFloat) {
        let clamped = min(max(value, 1), 5)
        if abs(clamped - zoom) > 0.001 {
            zoom = clamped
        }
    }

    func resetZoom() {
        bridge.resetZoom()
    }

    // MARK: Overlays

    func showHelp() {
        isPageEntryVisible = false
        pageEntryText = ""
        isHelpVisible = true
        chrome.hideAll()
    }

    func hideHelp() {
        guard isHelpVisible else { return }
        isHelpVisible = false
        bridge.focus()
    }

    func toggleHelp() {
        if isHelpVisible {
            hideHelp()
        } else {
            showHelp()
        }
    }

    func beginPageEntry() {
        guard totalPages > 0 else { return }
        isHelpVisible = false
        isPageEntryVisible = true
        pageEntryText = ""
        chrome.hideAll()
    }

    func cancelPageEntry() {
        guard isPageEntryVisible else { return }
        isPageEntryVisible = false
        pageEntryText = ""
        bridge.focus()
    }

    func commitPageEntry() {
        guard isPageEntryVisible else { return }
        let text = pageEntryText
        isPageEntryVisible = false
        pageEntryText = ""
        bridge.focus()

        guard let index = ReaderInteraction.pageIndex(from: text, pageCount: totalPages) else {
            showToast(tf(.toastInvalidPage, totalPages))
            return
        }
        goToPage(index)
    }

    // MARK: Progress

    func recordProgress(force: Bool = false) {
        guard !pageSlots.isEmpty else { return }
        guard force || currentPageIndex >= 0 else { return }
        let completed = currentPageIndex >= pageSlots.count - 1
        model?.recordProgress(
            manga: manga,
            chapter: chapter,
            pageIndex: currentPageIndex,
            isCompleted: completed
        )
    }

    func close() {
        metadataTask?.cancel()
        if !pageSlots.isEmpty {
            recordProgress(force: true)
        }
        chrome.hideAll()
        isHelpVisible = false
        isPageEntryVisible = false
        pageEntryText = ""
        toastTask?.cancel()
    }

    func dismiss() {
        model?.closeReader()
    }

    // MARK: Toast

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled, let self else { return }
            self.toast = nil
        }
    }
}
