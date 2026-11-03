import Foundation
import XCTest

@testable import Mangla

final class ReadingSessionTests: XCTestCase {
    @MainActor
    func testChapterSwitchClearsWebtoonSeekRequest() throws {
        let model = AppModel()
        model.persistenceEnabled = false

        let firstChapter = chapter(id: "chapter-1", name: "1")
        let secondChapter = chapter(id: "chapter-2", name: "2")
        let manga = MangaItem(
            id: "manga",
            title: "Manga",
            containerURL: URL(fileURLWithPath: "/tmp/Manga"),
            chapters: [firstChapter, secondChapter]
        )
        let collectionID = UUID()
        model.collections = [
            MangaCollection(
                id: collectionID,
                name: "Collection",
                directoryURL: URL(fileURLWithPath: "/tmp/Collection"),
                mangas: [manga],
                isAvailable: true,
                lastMangaID: nil,
                bookmark: nil
            )
        ]
        model.selectedCollectionID = collectionID

        let session = ReadingSession(model: model, manga: manga, chapter: firstChapter)
        session.seekRequest = WebtoonSeekRequest(id: 7, page: 2)

        session.nextChapter()

        XCTAssertEqual(session.chapter.id, secondChapter.id)
        XCTAssertEqual(session.seekRequest, WebtoonSeekRequest(id: 0, page: 0))
    }

    @MainActor
    func testChapterPickerFiltersAndOpensAnotherChapter() {
        let model = AppModel()
        model.persistenceEnabled = false

        let chapters = [
            chapter(id: "chapter-1", name: "Volume 1"),
            chapter(id: "chapter-2", name: "Volume 2"),
            chapter(id: "chapter-3", name: "Bonus"),
        ]
        let manga = MangaItem(
            id: "manga",
            title: "Manga",
            containerURL: URL(fileURLWithPath: "/tmp/Manga"),
            chapters: chapters
        )
        let collectionID = UUID()
        model.collections = [
            MangaCollection(
                id: collectionID,
                name: "Collection",
                directoryURL: URL(fileURLWithPath: "/tmp/Collection"),
                mangas: [manga],
                isAvailable: true,
                lastMangaID: nil,
                bookmark: nil
            )
        ]
        model.selectedCollectionID = collectionID

        let session = ReadingSession(model: model, manga: manga, chapter: chapters[0])
        defer { session.close() }

        session.showChapterPicker()
        XCTAssertTrue(session.isChapterPickerVisible)

        session.chapterQuery = "volume"
        XCTAssertEqual(session.chapterEntries.map(\.chapter.id), ["chapter-1", "chapter-2"])

        session.openChapter(chapters[1])

        XCTAssertFalse(session.isChapterPickerVisible)
        XCTAssertEqual(session.chapterQuery, "")
        XCTAssertEqual(session.chapter.id, "chapter-2")
    }

    private func chapter(id: String, name: String) -> ChapterItem {
        ChapterItem(
            id: id,
            title: name,
            containerURL: URL(fileURLWithPath: "/tmp/\(id)"),
            pages: [
                PageItem(url: URL(fileURLWithPath: "/tmp/\(id)/1.jpg")),
                PageItem(url: URL(fileURLWithPath: "/tmp/\(id)/2.jpg")),
            ]
        )
    }

    @MainActor
    func testScrollProgressIsCoalescedUntilTheScrollPauses() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManglaScrollProgress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var pages: [PageItem] = []
        for index in 1...3 {
            let url = root.appendingPathComponent("\(index).png")
            try ImageFixture.pngData(width: 40, height: 60).write(to: url)
            pages.append(PageItem(url: url))
        }

        let chapter = ChapterItem(id: "chapter", title: "1", containerURL: root, pages: pages)
        let manga = MangaItem(id: "manga", title: "Manga", containerURL: root, chapters: [chapter])
        let collectionID = UUID()
        let model = AppModel()
        model.persistenceEnabled = false
        model.collections = [
            MangaCollection(
                id: collectionID,
                name: "Collection",
                directoryURL: root,
                mangas: [manga],
                isAvailable: true,
                lastMangaID: manga.id,
                bookmark: nil
            )
        ]
        model.selectedCollectionID = collectionID

        let session = ReadingSession(
            model: model,
            manga: manga,
            chapter: chapter,
            progressDelay: .milliseconds(120)
        )
        defer { session.close() }

        for _ in 0..<400 where session.isLoadingChapter {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(session.isLoadingChapter)
        XCTAssertEqual(model.progress[manga.id]?.chapters[chapter.id]?.pageIndex, 0)

        session.noteVisiblePage(2)
        XCTAssertEqual(session.currentPageIndex, 2)
        XCTAssertEqual(
            model.progress[manga.id]?.chapters[chapter.id]?.pageIndex,
            0,
            "Each scrolled page must not rewrite progress and redraw the library"
        )

        await session.waitForPendingProgress()
        XCTAssertEqual(model.progress[manga.id]?.chapters[chapter.id]?.pageIndex, 2)
    }

    @MainActor
    func testClosingTheReaderFlushesPendingScrollProgress() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManglaScrollFlush-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("1.png")
        try ImageFixture.pngData(width: 40, height: 60).write(to: url)
        let chapter = ChapterItem(
            id: "chapter",
            title: "1",
            containerURL: root,
            pages: [PageItem(url: url), PageItem(url: url)]
        )
        let manga = MangaItem(id: "manga", title: "Manga", containerURL: root, chapters: [chapter])
        let collectionID = UUID()
        let model = AppModel()
        model.persistenceEnabled = false
        model.collections = [
            MangaCollection(
                id: collectionID,
                name: "Collection",
                directoryURL: root,
                mangas: [manga],
                isAvailable: true,
                lastMangaID: manga.id,
                bookmark: nil
            )
        ]
        model.selectedCollectionID = collectionID

        let session = ReadingSession(
            model: model,
            manga: manga,
            chapter: chapter,
            progressDelay: .seconds(30)
        )
        for _ in 0..<400 where session.isLoadingChapter {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(session.isLoadingChapter)

        session.noteVisiblePage(1)
        session.close()

        XCTAssertEqual(model.progress[manga.id]?.chapters[chapter.id]?.pageIndex, 1)
    }
}
