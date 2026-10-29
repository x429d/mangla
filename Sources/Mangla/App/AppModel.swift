import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    // Library
    var projectURL: URL?
    var projectName = "Mangla"
    var mangas: [MangaItem] = []
    var progress: [String: MangaProgress] = [:]
    var lastMangaID: String?
    var filter: LibraryFilter = .all
    var searchText = ""
    var expandedMangaIDs: Set<String> = []
    var columnVisibility: NavigationSplitViewVisibility = .all

    // Reader
    let bridge = ReaderBridge()
    var reading: ReadingSession?

    // Status
    var isLoadingProject = false
    var isScanning = false
    var errorMessage: String?

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var rescanTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: ProjectWatcher?
    @ObservationIgnored private var securityScopedURL: URL?
    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var pendingAutoReader = false

    // MARK: - Bootstrap

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        let state = StatePersistence.load()
        progress = state?.progress ?? [:]
        lastMangaID = state?.lastMangaID

        let arguments = CommandLine.arguments
        pendingAutoReader = arguments.contains("--open-reader")

        var initialURL: URL?
        var isLaunchArgument = false
        if let index = arguments.firstIndex(of: "--project"), index + 1 < arguments.count {
            initialURL = URL(fileURLWithPath: arguments[index + 1])
            isLaunchArgument = true
        } else if let saved = WorkspaceBookmark.resolve() {
            initialURL = saved
        } else if let path = state?.projectPath {
            initialURL = URL(fileURLWithPath: path)
        }

        guard let initialURL else {
            isLoadingProject = false
            return
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: initialURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            errorMessage = "Папка проекта больше недоступна: \(initialURL.path)"
            isLoadingProject = false
            return
        }

        let standardized = initialURL.standardizedFileURL
        let resolvedPath = canonicalPath(standardized)
        if let savedPath = state?.projectPath,
           canonicalPath(URL(fileURLWithPath: savedPath)) != resolvedPath {
            // A different project: relative-path progress keys would collide.
            progress = [:]
            lastMangaID = nil
        }

        if isLaunchArgument {
            WorkspaceBookmark.save(standardized)
        }

        access(standardized)
        projectURL = standardized
        projectName = standardized.lastPathComponent
        isLoadingProject = true
        scan(showSpinner: true)
    }

    func shutdown() {
        reading?.close()
        saveTask?.cancel()
        StatePersistence.saveSynchronously(makeState())
        watcher?.stop()
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Project handling

    func chooseProject() {
        let panel = NSOpenPanel()
        panel.title = "Выберите папку проекта"
        panel.message = "Внутри должны лежать папки с мангой или главами."
        panel.prompt = "Открыть проект"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if let projectURL {
            panel.directoryURL = projectURL.deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setProject(url)
    }

    func setProject(_ url: URL) {
        let standardized = url.standardizedFileURL
        if let projectURL, canonicalPath(projectURL) == canonicalPath(standardized) {
            scan(showSpinner: true)
            return
        }

        reading?.close()
        reading = nil
        watcher?.stop()
        watcher = nil

        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
        access(standardized)
        WorkspaceBookmark.save(standardized)

        projectURL = standardized
        projectName = standardized.lastPathComponent
        mangas = []
        progress = [:]
        lastMangaID = nil
        expandedMangaIDs = []
        filter = .all
        searchText = ""
        errorMessage = nil
        isLoadingProject = true
        scan(showSpinner: true)
    }

    func forgetProject() {
        reading?.close()
        reading = nil
        watcher?.stop()
        watcher = nil
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
        WorkspaceBookmark.clear()
        projectURL = nil
        projectName = "Mangla"
        mangas = []
        progress = [:]
        lastMangaID = nil
        expandedMangaIDs = []
        isLoadingProject = false
        saveNow()
    }

    func refresh() {
        scan(showSpinner: false)
    }

    func revealProject() {
        guard let projectURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([projectURL])
    }

    func reveal(manga: MangaItem) {
        NSWorkspace.shared.activateFileViewerSelecting([manga.directoryURL])
    }

    private func access(_ url: URL) {
        if url.startAccessingSecurityScopedResource() {
            securityScopedURL = url
        }
    }

    private func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    // MARK: - Scanning

    private func scan(showSpinner: Bool) {
        guard let projectURL else { return }
        scanTask?.cancel()
        if showSpinner { isLoadingProject = true }
        isScanning = true
        let url = projectURL

        scanTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<ProjectSnapshot, LibraryScanError> in
                do {
                    return .success(try LibraryScanner.scan(projectURL: url))
                } catch let error as LibraryScanError {
                    return .failure(error)
                } catch {
                    return .failure(.unreadable(url))
                }
            }.value

            guard !Task.isCancelled, let self else { return }
            self.isScanning = false
            self.isLoadingProject = false
            switch result {
            case .success(let snapshot):
                self.apply(snapshot)
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func apply(_ snapshot: ProjectSnapshot) {
        mangas = snapshot.mangas
        projectName = snapshot.name

        if let reading {
            let stillExists = mangas.contains { manga in
                manga.id == reading.manga.id
                    && manga.chapters.contains { $0.id == reading.chapter.id }
            }
            if !stillExists { closeReader() }
        }

        if let lastMangaID, !mangas.contains(where: { $0.id == lastMangaID }) {
            self.lastMangaID = mangas.first?.id
        }
        if let lastMangaID {
            expandedMangaIDs.insert(lastMangaID)
        }
        if let reading {
            expandedMangaIDs.insert(reading.manga.id)
        }

        startWatchers(snapshot)
        saveNow()

        if pendingAutoReader {
            pendingAutoReader = false
            if let target = autoOpenTarget {
                openReader(manga: target.manga, chapter: target.chapter, startPage: target.pageIndex)
            }
        }
    }

    private func startWatchers(_ snapshot: ProjectSnapshot) {
        watcher?.stop()
        watcher = ProjectWatcher(
            root: snapshot.projectURL,
            mangaDirectories: snapshot.mangas.map(\.directoryURL)
        ) { [weak self] in
            self?.scheduleRescan()
        }
    }

    private func scheduleRescan() {
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled, let self else { return }
            self.scan(showSpinner: false)
        }
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
        expandedMangaIDs.insert(manga.id)
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
        LibraryState(
            projectPath: projectURL.map { canonicalPath($0) },
            lastMangaID: lastMangaID,
            progress: progress
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

    func openReader(manga: MangaItem, chapter: ChapterItem? = nil, startPage: Int? = nil, restart: Bool = false) {
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
        expandedMangaIDs.insert(manga.id)
    }

    func openChapter(_ chapter: ChapterItem, manga: MangaItem, restart: Bool = false) {
        openReader(manga: manga, chapter: chapter, startPage: restart ? 0 : nil, restart: restart)
    }

    /// "Start over" from a card or sidebar row: clears the manga's progress and
    /// opens its first chapter from the first page.
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

    func nextReadingTarget(afterMangaID mangaID: String, chapterID: String) -> (manga: MangaItem, chapter: ChapterItem)? {
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

    func previousReadingTarget(afterMangaID mangaID: String, chapterID: String) -> (manga: MangaItem, chapter: ChapterItem)? {
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

    // MARK: - Sidebar helpers

    func toggleSidebar() {
        withAnimation(.smooth(duration: 0.25)) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    func toggleExpanded(mangaID: String) {
        if expandedMangaIDs.contains(mangaID) {
            expandedMangaIDs.remove(mangaID)
        } else {
            expandedMangaIDs.insert(mangaID)
        }
    }

    func clearFilters() {
        searchText = ""
        filter = .all
    }

    func clearError() {
        errorMessage = nil
    }
}
