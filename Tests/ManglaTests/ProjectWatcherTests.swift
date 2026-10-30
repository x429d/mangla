import Foundation
import XCTest

@testable import Mangla

final class ProjectWatcherTests: XCTestCase {
    @MainActor
    func testWatchingChapterDirectorySeesNewPages() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManglaWatcher-\(UUID().uuidString)", isDirectory: true)
        let manga = root.appendingPathComponent("Manga", isDirectory: true)
        let chapter = manga.appendingPathComponent("Chapter 1", isDirectory: true)
        try FileManager.default.createDirectory(at: chapter, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let changed = expectation(description: "chapter change")
        var fired = false
        let watcher = ProjectWatcher(
            root: root,
            mangaDirectories: [manga],
            chapterDirectories: [chapter]
        ) {
            guard !fired else { return }
            fired = true
            changed.fulfill()
        }
        defer { watcher.stop() }

        try Data().write(to: chapter.appendingPathComponent("001.jpg"))
        await fulfillment(of: [changed], timeout: 2)
    }
}
