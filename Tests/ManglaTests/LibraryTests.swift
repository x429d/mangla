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
