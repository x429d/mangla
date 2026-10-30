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
            directoryURL: URL(fileURLWithPath: "/tmp/Manga"),
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

    private func chapter(id: String, name: String) -> ChapterItem {
        ChapterItem(
            id: id,
            title: name,
            directoryURL: URL(fileURLWithPath: "/tmp/\(id)"),
            pages: [
                PageItem(url: URL(fileURLWithPath: "/tmp/\(id)/1.jpg")),
                PageItem(url: URL(fileURLWithPath: "/tmp/\(id)/2.jpg")),
            ]
        )
    }
}
