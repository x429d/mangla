import AppKit
import Observation
import SwiftUI

// MARK: - Canvas bridge

@MainActor
protocol ReaderCanvasControlling: AnyObject {
    func resetZoom(animated: Bool)
    func zoomIn()
    func zoomOut()
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

    func resetZoom() { canvas?.resetZoom(animated: true) }
    func zoomIn() { canvas?.zoomIn() }
    func zoomOut() { canvas?.zoomOut() }
    func focus() { canvas?.focusCanvas() }
}

// MARK: - Floating HUD state

@MainActor
@Observable
final class ReaderChromeState {
    var isVisible = true
    var isHovering = false

    @ObservationIgnored private var hideTask: Task<Void, Never>?

    func poke() {
        isVisible = true
        scheduleHide()
    }

    /// Scrolling should not summon the HUD, but it should keep it alive.
    func noteScrollActivity() {
        if isVisible {
            scheduleHide()
        }
    }

    func hold() {
        hideTask?.cancel()
        hideTask = nil
        isVisible = true
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
        if hovering {
            hold()
        } else {
            scheduleHide()
        }
    }

    func scheduleHide(after seconds: Double = 2.0) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, !self.isHovering else { return }
            self.isVisible = false
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    func cancel() {
        hideTask?.cancel()
        hideTask = nil
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

        let resumePage = startPage
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
            chrome.poke()
        }
    }

    var fitMode: FitMode {
        get { storedFitMode }
        set {
            guard newValue != storedFitMode else { return }
            storedFitMode = newValue
            ReaderPreferences.fitMode = newValue
            zoom = 1
            chrome.poke()
        }
    }

    var direction: ReadingDirection {
        get { storedDirection }
        set {
            storedDirection = newValue
            ReaderPreferences.direction = newValue
            chrome.poke()
        }
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
            self.chrome.poke()
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

    func next() {
        chrome.poke()
        switch storedLayoutMode {
        case .single, .spread:
            if spreadIndex + 1 < spreads.count {
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
        chrome.poke()
        switch storedLayoutMode {
        case .single, .spread:
            if spreadIndex > 0 {
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
        chrome.poke()
        switch storedLayoutMode {
        case .single, .spread:
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
            showToast("Это последняя глава в проекте")
            return
        }
        switchTo(manga: target.manga, chapter: target.chapter, startPage: 0)
    }

    func previousChapter() {
        guard let target = model?.previousReadingTarget(afterMangaID: manga.id, chapterID: chapter.id) else {
            showToast("Это первая глава в проекте")
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
        loadMetadata(startPage: startPage)

        let subtitle = newManga.id == previousMangaID
            ? newChapter.title
            : "\(newManga.title) · \(newChapter.title)"
        showToast("Дальше: \(subtitle)")
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
        chrome.poke()
        bridge.resetZoom()
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
        chrome.cancel()
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
