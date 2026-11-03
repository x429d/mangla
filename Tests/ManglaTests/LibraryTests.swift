import Foundation
import XCTest

@testable import Mangla

final class LibraryScannerTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ManglaTests-\(UUID().uuidString)", isDirectory: true)

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testNaturalSortIgnoresExtension() throws {
        let manga = root.appendingPathComponent("Berserk", isDirectory: true)
        try FileManager.default.createDirectory(at: manga, withIntermediateDirectories: true)
        for name in ["20.webp", "1.webp", "10.jpg", "2.webp", "3.jpg", "4.jpg", "6.webp"] {
            try Data().write(to: manga.appendingPathComponent(name))
        }

        let snapshot = try LibraryScanner.scan(projectURL: root)
        XCTAssertEqual(snapshot.mangas.count, 1)
        let chapter = try XCTUnwrap(snapshot.mangas.first?.chapters.first)
        XCTAssertEqual(chapter.pages.map(\.name), ["1", "2", "3", "4", "6", "10", "20"])
        XCTAssertEqual(chapter.pages.map(\.fileExtension), ["webp", "webp", "jpg", "jpg", "webp", "jpg", "webp"])
    }

    func testChapterFoldersAreSortedNaturally() throws {
        let manga = root.appendingPathComponent("One Piece", isDirectory: true)
        for chapter in ["Chapter 10", "Chapter 2", "Chapter 1"] {
            let folder = manga.appendingPathComponent(chapter, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data().write(to: folder.appendingPathComponent("001.jpg"))
            try Data().write(to: folder.appendingPathComponent("002.jpg"))
        }

        let snapshot = try LibraryScanner.scan(projectURL: root)
        let chapters = try XCTUnwrap(snapshot.mangas.first?.chapters)
        XCTAssertEqual(chapters.map(\.title), ["Chapter 1", "Chapter 2", "Chapter 10"])
        XCTAssertEqual(snapshot.mangas.first?.pageCount, 6)
    }

    func testMangaRootCoverDoesNotSwallowChapters() throws {
        let manga = root.appendingPathComponent("Blue Period", isDirectory: true)
        try FileManager.default.createDirectory(at: manga, withIntermediateDirectories: true)
        try Data().write(to: manga.appendingPathComponent("cover.jpg"))
        let chapter = manga.appendingPathComponent("Season 1", isDirectory: true)
        try FileManager.default.createDirectory(at: chapter, withIntermediateDirectories: true)
        for index in 1...3 {
            try Data().write(to: chapter.appendingPathComponent("\(index).png"))
        }

        let snapshot = try LibraryScanner.scan(projectURL: root)
        let mangaItem = try XCTUnwrap(snapshot.mangas.first)
        XCTAssertEqual(mangaItem.chapters.count, 1)
        XCTAssertEqual(mangaItem.chapters[0].title, "Season 1")
        XCTAssertEqual(mangaItem.chapters[0].pageCount, 3)
    }

    func testChapterNestedDeeperThanTheProbeLimitIsFound() throws {
        let manga = root.appendingPathComponent("Deep", isDirectory: true)
        let chapter =
            manga
            .appendingPathComponent("Part 1", isDirectory: true)
            .appendingPathComponent("Part 2", isDirectory: true)
            .appendingPathComponent("Part 3", isDirectory: true)
            .appendingPathComponent("Part 4", isDirectory: true)
            .appendingPathComponent("Part 5", isDirectory: true)
        try FileManager.default.createDirectory(at: chapter, withIntermediateDirectories: true)
        try Data().write(to: chapter.appendingPathComponent("001.jpg"))
        try Data().write(to: chapter.appendingPathComponent("002.jpg"))

        let snapshot = try LibraryScanner.scan(projectURL: root)
        let mangaItem = try XCTUnwrap(snapshot.mangas.first)
        XCTAssertEqual(mangaItem.chapters.count, 1)
        XCTAssertEqual(mangaItem.chapters[0].pageCount, 2)
        XCTAssertEqual(mangaItem.chapters[0].title, "Part 1/Part 2/Part 3/Part 4/Part 5")
    }

    func testUnreadableRootThrowsInsteadOfLookingEmpty() throws {
        let locked = root.appendingPathComponent("Locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
        }

        XCTAssertThrowsError(try LibraryScanner.scan(projectURL: locked)) { error in
            guard case LibraryScanError.unreadable = error else {
                return XCTFail("Expected unreadable, got \(error)")
            }
        }
    }

    func testProjectFolderItselfCanBeAManga() throws {
        for index in 1...3 {
            try Data().write(to: root.appendingPathComponent("\(index).webp"))
        }

        let snapshot = try LibraryScanner.scan(projectURL: root)
        XCTAssertEqual(snapshot.mangas.count, 1)
        XCTAssertEqual(snapshot.mangas[0].chapters.count, 1)
        XCTAssertEqual(snapshot.mangas[0].pageCount, 3)
    }
}

final class SpreadBuilderTests: XCTestCase {
    private func page(_ width: CGFloat, _ height: CGFloat) -> PageSlot {
        PageSlot(
            url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString).jpg"), pixelSize: CGSize(width: width, height: height))
    }

    func testWideScanKeepsParity() {
        let pages = [
            page(1000, 1500),
            page(1000, 1500),
            page(2000, 1200),
            page(1000, 1500),
            page(1000, 1500),
            page(1000, 1500),
        ]
        let spreads = SpreadBuilder.spreads(pages: pages, mode: .spread)
        XCTAssertEqual(spreads.map(\.pageIndices), [[0, 1], [2], [3, 4], [5]])
    }

    func testCoverOffsetKeepsTheFirstPageAlone() {
        let pages = (0..<5).map { _ in page(1000, 1500) }
        let spreads = SpreadBuilder.spreads(
            pages: pages,
            mode: .spread,
            firstPageAsCover: true
        )
        XCTAssertEqual(spreads.map(\.pageIndices), [[0], [1, 2], [3, 4]])
    }

    func testCoverOffsetResumesPairingAfterAWideCover() {
        let pages = [
            page(2000, 1200),
            page(1000, 1500),
            page(1000, 1500),
            page(1000, 1500),
        ]
        let spreads = SpreadBuilder.spreads(
            pages: pages,
            mode: .spread,
            firstPageAsCover: true
        )
        XCTAssertEqual(spreads.map(\.pageIndices), [[0], [1, 2], [3]])
    }

    func testWithoutCoverOffsetPairingStartsAtZero() {
        let pages = (0..<5).map { _ in page(1000, 1500) }
        let spreads = SpreadBuilder.spreads(pages: pages, mode: .spread)
        XCTAssertEqual(spreads.map(\.pageIndices), [[0, 1], [2, 3], [4]])
    }

    func testSingleModeProducesOneSpreadPerPage() {
        let pages = [page(1000, 1500), page(1000, 1500), page(1000, 1500)]
        let spreads = SpreadBuilder.spreads(pages: pages, mode: .single)
        XCTAssertEqual(spreads.map(\.pageIndices), [[0], [1], [2]])
    }

    func testWebtoonProgression() {
        let pages = [page(1000, 1500), page(1000, 1500)]
        XCTAssertEqual(
            SpreadBuilder.spreads(pages: pages, mode: .webtoon).map(\.pageIndices),
            [[0], [1]]
        )
    }
}

final class PageLayoutTests: XCTestCase {
    private let portrait = PageSlot(
        url: URL(fileURLWithPath: "/tmp/a.jpg"),
        pixelSize: CGSize(width: 1000, height: 1500)
    )

    func testFitHeight() {
        let layout = PageLayoutCalculator.layout(
            slots: [portrait],
            fit: .fitHeight,
            viewport: CGSize(width: 1000, height: 800)
        )
        XCTAssertEqual(layout.containerSize.width, 1000, accuracy: 0.6)
        XCTAssertEqual(layout.containerSize.height, 800, accuracy: 0.6)
        XCTAssertEqual(layout.surfaceRect.width, 533.33, accuracy: 1)
        XCTAssertEqual(layout.surfaceRect.height, 800, accuracy: 0.6)
        XCTAssertEqual(layout.surfaceRect.midX, 500, accuracy: 0.6)
    }

    func testFitWidthAllowsVerticalOverflow() {
        let layout = PageLayoutCalculator.layout(
            slots: [portrait],
            fit: .fitWidth,
            viewport: CGSize(width: 1000, height: 800)
        )
        XCTAssertEqual(layout.containerSize.width, 1000, accuracy: 0.6)
        XCTAssertEqual(layout.containerSize.height, 1500, accuracy: 0.6)
        XCTAssertEqual(layout.surfaceRect, CGRect(x: 0, y: 0, width: 1000, height: 1500))
    }

    func testOriginalSize() {
        let layout = PageLayoutCalculator.layout(
            slots: [portrait],
            fit: .original,
            viewport: CGSize(width: 1200, height: 800)
        )
        XCTAssertEqual(layout.containerSize.width, 1200, accuracy: 0.6)
        XCTAssertEqual(layout.containerSize.height, 1500, accuracy: 0.6)
        XCTAssertEqual(layout.surfaceRect.size.width, 1000, accuracy: 0.6)
        XCTAssertEqual(layout.surfaceRect.midX, 600, accuracy: 0.6)
    }

    func testTwoPageSpreadFitsWidth() {
        let layout = PageLayoutCalculator.layout(
            slots: [portrait, portrait],
            fit: .fitWidth,
            viewport: CGSize(width: 1000, height: 800)
        )
        XCTAssertEqual(layout.surfaceRect.width, 1000, accuracy: 0.6)
        XCTAssertEqual(layout.pageRects.count, 2)
        XCTAssertEqual(layout.pageRects[0].maxX, layout.pageRects[1].minX, accuracy: 0.6)
    }
}

final class ChapterIndexTests: XCTestCase {
    private func chapter(_ title: String, _ index: Int) -> ChapterItem {
        ChapterItem(
            id: "chapter-\(index)",
            title: title,
            containerURL: URL(fileURLWithPath: "/tmp/chapter-\(index)"),
            pages: []
        )
    }

    func testSearchKeepsOriginalChapterNumbers() {
        let chapters = [
            chapter("Volume 1", 0),
            chapter("Bonus", 1),
            chapter("Volume 2", 2),
        ]

        let entries = ChapterIndex.entries(chapters, query: "volume")
        XCTAssertEqual(entries.map(\.chapter.title), ["Volume 1", "Volume 2"])
        XCTAssertEqual(entries.map(\.index), [0, 2])
        XCTAssertEqual(entries.map(\.id), ["chapter-0", "chapter-2"])
    }

    func testEmptySearchKeepsEveryChapter() {
        let chapters = [chapter("1", 0), chapter("2", 1)]
        XCTAssertEqual(ChapterIndex.filter(chapters, query: "   ").count, 2)
        XCTAssertTrue(ChapterIndex.filter(chapters, query: "missing").isEmpty)
    }
}

final class ChapterMenuTests: XCTestCase {
    private func chapter(_ index: Int) -> ChapterItem {
        ChapterItem(
            id: "chapter-\(index)",
            title: "\(index + 1)",
            containerURL: URL(fileURLWithPath: "/tmp/chapter-\(index)"),
            pages: []
        )
    }

    func testLongMenusAreSplitIntoRanges() {
        let chapters = (0..<95).map(chapter)
        let groups = ChapterMenu.groups(chapters)

        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.map(\.lowerBound), [1, 41, 81])
        XCTAssertEqual(groups.map(\.upperBound), [40, 80, 95])
        XCTAssertEqual(groups.map(\.chapters.count), [40, 40, 15])
        XCTAssertEqual(groups[2].chapters.first?.id, chapters[80].id)
    }

    func testShortMenusStayInOneGroup() {
        let groups = ChapterMenu.groups((0..<7).map(chapter), size: 10)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].lowerBound, 1)
        XCTAssertEqual(groups[0].upperBound, 7)
    }

    func testEmptyMenuHasNoGroups() {
        XCTAssertTrue(ChapterMenu.groups([]).isEmpty)
    }
}

final class LibraryOrderingTests: XCTestCase {
    private func manga(
        id: String,
        title: String,
        chapters: Int,
        addedAt: Date? = nil
    ) -> MangaItem {
        let chapterItems = (0..<chapters).map { index in
            ChapterItem(
                id: "\(id)-chapter-\(index)",
                title: "\(index + 1)",
                containerURL: URL(fileURLWithPath: "/tmp/\(id)-\(index)"),
                pages: []
            )
        }
        return MangaItem(
            id: id,
            title: title,
            containerURL: URL(fileURLWithPath: "/tmp/\(id)"),
            chapters: chapterItems,
            addedAt: addedAt
        )
    }

    private func progress(_ updatedAt: Date) -> MangaProgress {
        MangaProgress(chapters: [:], lastChapterID: nil, updatedAt: updatedAt)
    }

    func testNameSortIsNaturalAndCaseInsensitive() {
        let items = [
            manga(id: "b", title: "Volume 10", chapters: 1),
            manga(id: "a", title: "volume 2", chapters: 1),
            manga(id: "c", title: "Alpha", chapters: 1),
        ]
        let sorted = LibraryOrdering.sorted(items, by: .name, progress: [:])
        XCTAssertEqual(sorted.map(\.title), ["Alpha", "volume 2", "Volume 10"])
    }

    func testRecentSortPutsUnreadLast() {
        let now = Date()
        let items = [
            manga(id: "old", title: "Old", chapters: 1),
            manga(id: "new", title: "New", chapters: 1),
            manga(id: "unread", title: "Unread", chapters: 1),
        ]
        let reading = [
            "old": progress(now.addingTimeInterval(-3600)),
            "new": progress(now),
        ]
        let sorted = LibraryOrdering.sorted(items, by: .recent, progress: reading)
        XCTAssertEqual(sorted.map(\.id), ["new", "old", "unread"])
    }

    func testChapterCountSortIsDescending() {
        let items = [
            manga(id: "small", title: "Small", chapters: 1),
            manga(id: "large", title: "Large", chapters: 9),
            manga(id: "medium", title: "Medium", chapters: 4),
        ]
        let sorted = LibraryOrdering.sorted(items, by: .chapterCount, progress: [:])
        XCTAssertEqual(sorted.map(\.id), ["large", "medium", "small"])
    }

    func testDateAddedSortPutsNewestFirstAndMissingDatesLast() {
        let now = Date()
        let items = [
            manga(id: "old", title: "Old", chapters: 1, addedAt: now.addingTimeInterval(-7200)),
            manga(id: "new", title: "New", chapters: 1, addedAt: now),
            manga(id: "unknown", title: "Unknown", chapters: 1),
        ]
        let sorted = LibraryOrdering.sorted(items, by: .dateAdded, progress: [:])
        XCTAssertEqual(sorted.map(\.id), ["new", "old", "unknown"])
    }

    func testTiesFallBackToTitle() {
        let date = Date()
        let items = [
            manga(id: "b", title: "Beta", chapters: 1, addedAt: date),
            manga(id: "a", title: "Alpha", chapters: 1, addedAt: date),
        ]
        let sorted = LibraryOrdering.sorted(items, by: .dateAdded, progress: [:])
        XCTAssertEqual(sorted.map(\.id), ["a", "b"])
    }
}

final class LibrarySelectionTests: XCTestCase {
    private func manga(_ index: Int) -> MangaItem {
        MangaItem(
            id: "manga-\(index)",
            title: "Manga \(index)",
            containerURL: URL(fileURLWithPath: "/tmp/manga-\(index)"),
            chapters: []
        )
    }

    func testFirstMoveSelectsTheFirstCard() {
        let items = (0..<6).map(manga)
        XCTAssertEqual(
            LibrarySelection.move(from: nil, direction: .right, mangas: items, columns: 3),
            "manga-0"
        )
    }

    func testArrowsMoveWithinAndAcrossRows() {
        let items = (0..<7).map(manga)
        XCTAssertEqual(
            LibrarySelection.move(from: "manga-1", direction: .right, mangas: items, columns: 3),
            "manga-2"
        )
        XCTAssertEqual(
            LibrarySelection.move(from: "manga-1", direction: .down, mangas: items, columns: 3),
            "manga-4"
        )
        XCTAssertEqual(
            LibrarySelection.move(from: "manga-4", direction: .up, mangas: items, columns: 3),
            "manga-1"
        )
        XCTAssertEqual(
            LibrarySelection.move(from: "manga-0", direction: .left, mangas: items, columns: 3),
            "manga-0"
        )
        XCTAssertEqual(
            LibrarySelection.move(from: "manga-6", direction: .down, mangas: items, columns: 3),
            "manga-6"
        )
    }

    func testEmptyLibraryHasNoSelection() {
        XCTAssertNil(LibrarySelection.move(from: nil, direction: .down, mangas: [], columns: 4))
    }
}
