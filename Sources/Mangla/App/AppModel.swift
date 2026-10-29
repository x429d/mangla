import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    // Collections
    var collections: [MangaCollection] = []
    var selectedCollectionID: UUID?
    /// Keyed by collection UUID string, then by manga folder path.
    var progressByCollection: [String: [String: MangaProgress]] = [:]

    // Library browsing
    private var storedFilter: LibraryFilter = .all
    private var storedSearchText = ""

    var filter: LibraryFilter {
        get { storedFilter }
        set {
            guard newValue != storedFilter else { return }
            storedFilter = newValue
            libraryPage = 0
        }
    }

    var searchText: String {
        get { storedSearchText }
        set {
            guard newValue != storedSearchText else { return }
            storedSearchText = newValue
            libraryPage = 0
        }
    }

    var libraryPage = 0
    let pageSize = LibraryPagination.defaultPageSize
    var columnVisibility: NavigationSplitViewVisibility = .all

    // Reader
    var reading: ReadingSession?

    // Status
    var scanningCollectionIDs: Set<UUID> = []
    var errorMessage: String?

    @ObservationIgnored private var initialScanTask: Task<Void, Never>?
    @ObservationIgnored private var scanTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var rescanTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var watchers: [UUID: ProjectWatcher] = [:]
    @ObservationIgnored private var scopedURLs: [UUID: URL] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var pendingAutoReader = false

    // MARK: - Active collection

    var selectedCollection: MangaCollection? {
        guard let id = selectedCollectionID else { return nil }
        return collections.first { $0.id == id }
    }

    var selectedCollectionIndex: Int? {
        guard let id = selectedCollectionID else { return nil }
        return collections.firstIndex { $0.id == id }
    }

    var activeCollectionKey: String {
        selectedCollectionID?.uuidString ?? ""
    }

    var mangas: [MangaItem] {
        selectedCollection?.mangas ?? []
    }

    var projectURL: URL? {
        selectedCollection?.directoryURL
    }

    var projectName: String {
        selectedCollection?.name ?? "Коллекция"
    }

    var lastMangaID: String? {
        get { selectedCollection?.lastMangaID }
        set {
            guard let index = selectedCollectionIndex else { return }
            collections[index].lastMangaID = newValue
        }
    }

    var progress: [String: MangaProgress] {
        get { progressByCollection[activeCollectionKey] ?? [:] }
        set {
            guard let id = selectedCollectionID else { return }
            progressByCollection[id.uuidString] = newValue
        }
    }

    var hasCollections: Bool { !collections.isEmpty }

    var isScanning: Bool { !scanningCollectionIDs.isEmpty }

    var isScanningSelected: Bool {
        guard let id = selectedCollectionID else { return false }
        return scanningCollectionIDs.contains(id)
    }

    var isLoadingSelectedCollection: Bool {
        isScanningSelected && mangas.isEmpty
    }

    // MARK: - Bootstrap

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        let arguments = CommandLine.arguments
        pendingAutoReader = arguments.contains("--open-reader")

        let state = StatePersistence.load()
        progressByCollection = state?.progress ?? [:]
        var selectedID = state?.selectedCollectionID

        loadStoredCollections(state?.collections ?? [])

        if collections.isEmpty, let legacy = LegacyWorkspaceBookmark.resolveSaved(), isDirectory(legacy) {
            let id = UUID()
            let bookmark = SecurityBookmark.make(for: legacy)
            collections = [
                MangaCollection(
                    id: id,
                    name: legacy.lastPathComponent,
                    directoryURL: legacy,
                    mangas: [],
                    isAvailable: true,
                    lastMangaID: nil,
                    bookmark: bookmark
                )
            ]
            access(legacy, id: id)
            selectedID = id
        }

        if let index = arguments.firstIndex(of: "--project"), index + 1 < arguments.count {
            let url = URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL
            if isDirectory(url) {
                if let existing = collections.first(where: { canonicalPath($0.directoryURL) == canonicalPath(url) }) {
                    selectedID = existing.id
                } else {
                    let id = UUID()
                    let bookmark = SecurityBookmark.make(for: url)
                    collections.append(
                        MangaCollection(
                            id: id,
                            name: url.lastPathComponent,
                            directoryURL: url,
                            mangas: [],
                            isAvailable: true,
                            lastMangaID: nil,
                            bookmark: bookmark
                        )
                    )
                    access(url, id: id)
                    selectedID = id
                }
            } else {
                errorMessage = "Папка коллекции недоступна: \(url.path)"
            }
        }

        if let selectedID, collections.contains(where: { $0.id == selectedID }) {
            selectedCollectionID = selectedID
        } else {
            selectedCollectionID = collections.first?.id
        }

        guard !collections.isEmpty else {
            pendingAutoReader = false
            return
        }

        saveNow()
        startInitialScans()
    }

    private func loadStoredCollections(_ records: [StoredCollection]) {
        for record in records {
            let fallback = URL(fileURLWithPath: record.path)
            var resolved = record.bookmark.flatMap(SecurityBookmark.resolve) ?? fallback
            var available = isDirectory(resolved)
            var bookmark = record.bookmark

            // Migrate the old single-project bookmark when possible.
            if bookmark == nil,
               let legacy = LegacyWorkspaceBookmark.resolveSaved(),
               canonicalPath(legacy) == canonicalPath(fallback) || (!available && records.count == 1) {
                resolved = legacy
                available = isDirectory(legacy)
                bookmark = SecurityBookmark.make(for: legacy)
            }

            if bookmark == nil, available {
                bookmark = SecurityBookmark.make(for: resolved)
            }

            let name = record.name.isEmpty ? resolved.lastPathComponent : record.name
            collections.append(
                MangaCollection(
                    id: record.id,
                    name: name,
                    directoryURL: resolved,
                    mangas: [],
                    isAvailable: available,
                    lastMangaID: record.lastMangaID,
                    bookmark: bookmark
                )
            )

            if available {
                access(resolved, id: record.id)
            }
        }
    }

    private func startInitialScans() {
        let availableIDs = collections.filter(\.isAvailable).map(\.id)
        guard !availableIDs.isEmpty else {
            pendingAutoReader = false
            saveNow()
            return
        }

        scanningCollectionIDs.formUnion(availableIDs)

        var ordered = availableIDs
        if let selectedCollectionID, let index = ordered.firstIndex(of: selectedCollectionID) {
            ordered.remove(at: index)
            ordered.insert(selectedCollectionID, at: 0)
        }

        initialScanTask = Task { [weak self] in
            guard let self else { return }

            for id in ordered {
                if Task.isCancelled { return }
                await self.performScan(collectionID: id)
                self.scanningCollectionIDs.remove(id)

                if self.pendingAutoReader, id == self.selectedCollectionID {
                    self.pendingAutoReader = false
                    if let target = self.autoOpenTarget {
                        self.openReader(
                            manga: target.manga,
                            chapter: target.chapter,
                            startPage: target.pageIndex
                        )
                    }
                }
            }

            self.pendingAutoReader = false
            self.saveNow()
        }
    }

    func shutdown() {
        reading?.close()
        initialScanTask?.cancel()
        for task in scanTasks.values { task.cancel() }
        for task in rescanTasks.values { task.cancel() }
        for watcher in watchers.values { watcher.stop() }
        for url in scopedURLs.values { url.stopAccessingSecurityScopedResource() }
        saveTask?.cancel()
        StatePersistence.saveSynchronously(makeState())
    }

    // MARK: - Collections

    func addCollections() {
        let panel = NSOpenPanel()
        panel.title = "Добавить коллекции"
        panel.message = "Выберите одну или несколько папок с мангой или главами."
        panel.prompt = "Добавить"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        if let projectURL {
            panel.directoryURL = projectURL.deletingLastPathComponent()
        }
        guard panel.runModal() == .OK else { return }
        addCollections(urls: panel.urls)
    }

    func addCollections(urls: [URL]) {
        var added: [UUID] = []

        for raw in urls {
            let url = raw.standardizedFileURL
            guard isDirectory(url) else { continue }
            guard !collections.contains(where: { canonicalPath($0.directoryURL) == canonicalPath(url) }) else {
                continue
            }

            let id = UUID()
            let bookmark = SecurityBookmark.make(for: url)
            collections.append(
                MangaCollection(
                    id: id,
                    name: url.lastPathComponent,
                    directoryURL: url,
                    mangas: [],
                    isAvailable: true,
                    lastMangaID: nil,
                    bookmark: bookmark
                )
            )
            access(url, id: id)
            added.append(id)
        }

        guard !added.isEmpty else {
            if !urls.isEmpty {
                errorMessage = "Эти коллекции уже добавлены."
            }
            return
        }

        // Do not disrupt an active reading session; the new collections will
        // be available in the sidebar when the reader is closed.
        if reading == nil {
            selectedCollectionID = added[0]
            searchText = ""
            filter = .all
            libraryPage = 0
        }

        for id in added {
            scan(collectionID: id)
        }
        saveNow()
    }

    func selectCollection(_ id: UUID) {
        guard reading == nil else { return }
        guard collections.contains(where: { $0.id == id }) else { return }
        guard selectedCollectionID != id else { return }

        selectedCollectionID = id
        searchText = ""
        filter = .all
        libraryPage = 0
        saveNow()
    }

    func removeSelectedCollection() {
        guard let id = selectedCollectionID else { return }
        removeCollection(id)
    }

    func removeCollection(_ id: UUID) {
        guard reading == nil else { return }

        scanTasks[id]?.cancel()
        scanTasks[id] = nil
        rescanTasks[id]?.cancel()
        rescanTasks[id] = nil
        scanningCollectionIDs.remove(id)

        watchers[id]?.stop()
        watchers[id] = nil

        if let url = scopedURLs.removeValue(forKey: id) {
            url.stopAccessingSecurityScopedResource()
        }

        collections.removeAll { $0.id == id }
        progressByCollection[id.uuidString] = nil

        if selectedCollectionID == id {
            selectedCollectionID = collections.first?.id
            searchText = ""
            filter = .all
            libraryPage = 0
        }

        saveNow()
    }

    func refresh() {
        guard let id = selectedCollectionID else { return }
        scan(collectionID: id)
    }

    func revealProject() {
        guard let projectURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([projectURL])
    }

    func reveal(collection: MangaCollection) {
        NSWorkspace.shared.activateFileViewerSelecting([collection.directoryURL])
    }

    func reveal(manga: MangaItem) {
        NSWorkspace.shared.activateFileViewerSelecting([manga.directoryURL])
    }

    // MARK: - Scanning

    func scan(collectionID: UUID) {
        guard collections.contains(where: { $0.id == collectionID }) else { return }

        scanTasks[collectionID]?.cancel()
        scanningCollectionIDs.insert(collectionID)

        scanTasks[collectionID] = Task { [weak self] in
            guard let self else { return }
            await self.performScan(collectionID: collectionID)
            self.scanningCollectionIDs.remove(collectionID)
            self.scanTasks[collectionID] = nil
            self.saveNow()
        }
    }

    private func performScan(collectionID: UUID) async {
        guard let collection = collections.first(where: { $0.id == collectionID }) else { return }
        let url = collection.directoryURL

        let result = await Task.detached(priority: .userInitiated) { () -> Result<ProjectSnapshot, LibraryScanError> in
            do {
                return .success(try LibraryScanner.scan(projectURL: url))
            } catch let error as LibraryScanError {
                return .failure(error)
            } catch {
                return .failure(.unreadable(url))
            }
        }.value

        guard !Task.isCancelled else { return }

        switch result {
        case .success(let snapshot):
            apply(snapshot, to: collectionID)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ snapshot: ProjectSnapshot, to id: UUID) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }

        collections[index].mangas = snapshot.mangas
        collections[index].isAvailable = true
        if collections[index].name.isEmpty {
            collections[index].name = snapshot.name
        }

        if let last = collections[index].lastMangaID,
           !snapshot.mangas.contains(where: { $0.id == last }) {
            collections[index].lastMangaID = snapshot.mangas.first?.id
        }

        startWatcher(for: id)

        if id == selectedCollectionID, let reading {
            let stillExists = snapshot.mangas.contains { manga in
                manga.id == reading.manga.id
                    && manga.chapters.contains { $0.id == reading.chapter.id }
            }
            if !stillExists {
                closeReader()
            }
        }

        if id == selectedCollectionID {
            clampPage()
        }

        scheduleSave()
    }

    private func startWatcher(for id: UUID) {
        watchers[id]?.stop()
        watchers[id] = nil

        guard let collection = collections.first(where: { $0.id == id }), collection.isAvailable else {
            return
        }

        watchers[id] = ProjectWatcher(
            root: collection.directoryURL,
            mangaDirectories: collection.mangas.map(\.directoryURL)
        ) { [weak self] in
            self?.scheduleRescan(collectionID: id)
        }
    }

    private func scheduleRescan(collectionID: UUID) {
        rescanTasks[collectionID]?.cancel()
        rescanTasks[collectionID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            self?.scan(collectionID: collectionID)
        }
    }

    private func access(_ url: URL, id: UUID) {
        if url.startAccessingSecurityScopedResource() {
            scopedURLs[id] = url
        }
    }

    private func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    // MARK: - Filtering

    var filteredMangas: [MangaItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return mangas.filter { manga in
            if !query.isEmpty {
                let matchesManga = manga.title.localizedCaseInsensitiveContains(query)
                let matchesChapter = manga.chapters.contains {
                    $0.title.localizedCaseInsensitiveContains(query)
                }
                if !matchesManga, !matchesChapter { return false }
            }

            switch filter {
            case .all:
                return true
            case .reading:
                return status(for: manga) == .reading
            case .completed:
                return status(for: manga) == .completed
            }
        }
    }

    func filterCount(_ filter: LibraryFilter) -> Int {
        switch filter {
        case .all: mangas.count
        case .reading: mangas.count { status(for: $0) == .reading }
        case .completed: mangas.count { status(for: $0) == .completed }
        }
    }

    // MARK: - Pagination

    var pageCount: Int {
        LibraryPagination.pageCount(total: filteredMangas.count, pageSize: pageSize)
    }

    var currentPage: Int {
        LibraryPagination.clampedPage(libraryPage, total: filteredMangas.count, pageSize: pageSize)
    }

    var pageMangas: [MangaItem] {
        let all = filteredMangas
        let range = LibraryPagination.range(total: all.count, page: libraryPage, pageSize: pageSize)
        guard !range.isEmpty else { return [] }
        return Array(all[range])
    }

    var pageRangeText: String {
        LibraryPagination.rangeLabel(total: filteredMangas.count, page: libraryPage, pageSize: pageSize)
    }

    func nextPage() {
        guard currentPage + 1 < pageCount else { return }
        libraryPage = currentPage + 1
    }

    func previousPage() {
        guard currentPage > 0 else { return }
        libraryPage = currentPage - 1
    }

    func resetPage() {
        libraryPage = 0
    }

    func clampPage() {
        libraryPage = currentPage
    }

    // MARK: - Progress

    func status(for manga: MangaItem) -> ReadingStatus {
        guard let mp = progress[manga.id], !manga.chapters.isEmpty else { return .unread }
        let hasStarted = manga.chapters.contains { mp.chapters[$0.id] != nil }
        guard hasStarted else { return .unread }
        let allCompleted = manga.chapters.allSatisfy { mp.chapters[$0.id]?.isCompleted == true }
        return allCompleted ? .completed : .reading
    }

    func progressFraction(for manga: MangaItem) -> Double {
        guard manga.pageCount > 0, let mp = progress[manga.id] else { return 0 }
        var readPages = 0
        for chapter in manga.chapters {
            guard let cp = mp.chapters[chapter.id] else { continue }
            if cp.isCompleted {
                readPages += chapter.pageCount
            } else {
                readPages += min(chapter.pageCount, max(0, cp.pageIndex + 1))
            }
        }
        return min(1, Double(readPages) / Double(manga.pageCount))
    }

    func resumeChapter(for manga: MangaItem) -> ChapterItem? {
        guard !manga.chapters.isEmpty else { return nil }
        if let id = progress[manga.id]?.lastChapterID,
           let chapter = manga.chapters.first(where: { $0.id == id }) {
            return chapter
        }
        return manga.chapters.first
    }

    func resumePage(for manga: MangaItem, chapter: ChapterItem) -> Int {
        progress[manga.id]?.chapters[chapter.id]?.pageIndex ?? 0
    }

    func recordProgress(manga: MangaItem, chapter: ChapterItem, pageIndex: Int, isCompleted: Bool) {
        var mp = progress[manga.id] ?? MangaProgress()
        var cp = mp.chapters[chapter.id] ?? ChapterProgress(pageIndex: pageIndex, isCompleted: false)
        cp.pageIndex = max(0, pageIndex)
        cp.isCompleted = cp.isCompleted || isCompleted
        cp.updatedAt = .now
        mp.chapters[chapter.id] = cp
        mp.lastChapterID = chapter.id
        mp.updatedAt = .now
        progress[manga.id] = mp
        lastMangaID = manga.id
        scheduleSave()
    }

    func noteOpened(manga: MangaItem, chapter: ChapterItem) {
        var mp = progress[manga.id] ?? MangaProgress()
        mp.lastChapterID = chapter.id
        mp.updatedAt = .now
        progress[manga.id] = mp
        lastMangaID = manga.id
        scheduleSave()
    }

    func setMangaRead(_ manga: MangaItem, read: Bool) {
        if read {
            var mp = progress[manga.id] ?? MangaProgress()
            for chapter in manga.chapters {
                mp.chapters[chapter.id] = ChapterProgress(
                    pageIndex: max(0, chapter.pageCount - 1),
                    isCompleted: true
                )
            }
            mp.lastChapterID = manga.chapters.last?.id
            mp.updatedAt = .now
            progress[manga.id] = mp
        } else {
            progress[manga.id] = MangaProgress()
        }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        StatePersistence.saveQueued(makeState())
    }

    private func makeState() -> LibraryState {
        let records = collections.map { collection in
            StoredCollection(
                id: collection.id,
                name: collection.name,
                path: canonicalPath(collection.directoryURL),
                bookmark: collection.bookmark ?? SecurityBookmark.make(for: collection.directoryURL),
                lastMangaID: collection.lastMangaID
            )
        }

        return LibraryState(
            collections: records,
            selectedCollectionID: selectedCollectionID,
            progress: progressByCollection
        )
    }

    // MARK: - Reader lifecycle

    var autoOpenTarget: (manga: MangaItem, chapter: ChapterItem, pageIndex: Int)? {
        resumeTarget(requireProgress: false)
    }

    var continueTarget: (manga: MangaItem, chapter: ChapterItem, pageIndex: Int)? {
        resumeTarget(requireProgress: true, skipCompleted: true)
    }

    private func resumeTarget(
        requireProgress: Bool,
        skipCompleted: Bool = false
    ) -> (manga: MangaItem, chapter: ChapterItem, pageIndex: Int)? {
        guard !mangas.isEmpty else { return nil }

        let candidates = mangas.filter { manga in
            guard progress[manga.id] != nil else { return false }
            if skipCompleted, status(for: manga) != .reading { return false }
            return true
        }

        let mostRecent = candidates.max {
            (progress[$0.id]?.updatedAt ?? .distantPast) < (progress[$1.id]?.updatedAt ?? .distantPast)
        }

        let preferred = lastMangaID.flatMap { id in
            candidates.first { $0.id == id }
        }

        guard let manga = preferred ?? mostRecent ?? (requireProgress ? nil : mangas.first) else {
            return nil
        }
        if requireProgress, progress[manga.id] == nil { return nil }
        guard let chapter = resumeChapter(for: manga) else { return nil }

        let page = resumePage(for: manga, chapter: chapter)
        return (manga, chapter, page)
    }

    func openReader(
        manga: MangaItem,
        chapter: ChapterItem? = nil,
        startPage: Int? = nil,
        restart: Bool = false
    ) {
        guard selectedCollectionID != nil else { return }

        let selectedChapter: ChapterItem?
        if let chapter {
            selectedChapter = chapter
        } else if restart {
            selectedChapter = manga.chapters.first
        } else {
            selectedChapter = resumeChapter(for: manga)
        }
        guard let chapter = selectedChapter else { return }

        let page = restart ? 0 : (startPage ?? resumePage(for: manga, chapter: chapter))
        reading?.close()

        let session = ReadingSession(
            model: self,
            manga: manga,
            chapter: chapter,
            startPage: page
        )
        reading = session
        noteOpened(manga: manga, chapter: chapter)
    }

    func openChapter(_ chapter: ChapterItem, manga: MangaItem, restart: Bool = false) {
        openReader(manga: manga, chapter: chapter, startPage: restart ? 0 : nil, restart: restart)
    }

    /// Clears the manga's progress and opens its first chapter from the start.
    func restartManga(_ manga: MangaItem) {
        progress[manga.id] = MangaProgress()
        lastMangaID = manga.id
        scheduleSave()
        openReader(manga: manga, restart: true)
    }

    func closeReader() {
        reading?.close()
        reading = nil
    }

    func continueReading() {
        guard let target = continueTarget else { return }
        openReader(manga: target.manga, chapter: target.chapter, startPage: target.pageIndex)
    }

    // MARK: - Chapter ordering

    func nextReadingTarget(
        afterMangaID mangaID: String,
        chapterID: String
    ) -> (manga: MangaItem, chapter: ChapterItem)? {
        guard let mangaIndex = mangas.firstIndex(where: { $0.id == mangaID }) else { return nil }
        let manga = mangas[mangaIndex]

        if let chapterIndex = manga.chapters.firstIndex(where: { $0.id == chapterID }),
           chapterIndex + 1 < manga.chapters.count {
            return (manga, manga.chapters[chapterIndex + 1])
        }

        guard mangaIndex + 1 < mangas.count else { return nil }
        let nextManga = mangas[mangaIndex + 1]
        guard let chapter = nextManga.chapters.first else {
            return nextReadingTarget(afterMangaID: nextManga.id, chapterID: "")
        }
        return (nextManga, chapter)
    }

    func previousReadingTarget(
        afterMangaID mangaID: String,
        chapterID: String
    ) -> (manga: MangaItem, chapter: ChapterItem)? {
        guard let mangaIndex = mangas.firstIndex(where: { $0.id == mangaID }) else { return nil }
        let manga = mangas[mangaIndex]

        if let chapterIndex = manga.chapters.firstIndex(where: { $0.id == chapterID }),
           chapterIndex > 0 {
            return (manga, manga.chapters[chapterIndex - 1])
        }

        guard mangaIndex > 0 else { return nil }
        let previousManga = mangas[mangaIndex - 1]
        guard let chapter = previousManga.chapters.last else {
            return previousReadingTarget(afterMangaID: previousManga.id, chapterID: "")
        }
        return (previousManga, chapter)
    }

    // MARK: - Sidebar / small actions

    func toggleSidebar() {
        withAnimation(.smooth(duration: 0.25)) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    func clearFilters() {
        searchText = ""
        filter = .all
        libraryPage = 0
    }

    func clearError() {
        errorMessage = nil
    }
}
