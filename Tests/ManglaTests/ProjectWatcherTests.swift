import Darwin
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

        // fseventsd replays the newest history for a brand-new tree, so let
        // those events pass before the watcher starts and the assertion below
        // measures only the new page.
        try await Task.sleep(for: .milliseconds(1000))

        let changed = expectation(description: "chapter change")
        var fired = false
        let watcher = ProjectWatcher(root: root) {
            guard !fired else { return }
            fired = true
            changed.fulfill()
        }
        defer { watcher.stop() }

        // Give the stream time to start so the assertion below proves the
        // callback came from the new page and not from stream startup.
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(fired, "Watcher fired before the chapter changed")

        try Data().write(to: chapter.appendingPathComponent("001.jpg"))
        await fulfillment(of: [changed], timeout: 5)
    }

    /// A collection with many chapters used to hold one file descriptor per
    /// directory. Three large collections then exhausted the 256-descriptor
    /// limit macOS gives GUI apps, and every later image load failed.
    @MainActor
    func testWatcherDoesNotConsumeADescriptorPerDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManglaWatcherScale-\(UUID().uuidString)", isDirectory: true)
        for index in 0..<60 {
            let chapter = root.appendingPathComponent("Manga/Chapter \(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: chapter, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let before = openDescriptorCount()
        let watcher = ProjectWatcher(root: root) {}
        defer { watcher.stop() }
        let opened = openDescriptorCount() - before

        XCTAssertLessThanOrEqual(
            opened,
            8,
            "One stream per collection may not open \(opened) descriptors for 60 directories"
        )
    }

    func testOnlyStructuralEventsAreRelevant() {
        let chapter = "/Library/Manga/Chapter 1"
        XCTAssertTrue(
            ProjectWatcher.isRelevant(path: chapter, flags: directoryFlags(kFSEventStreamEventFlagItemCreated)))
        XCTAssertTrue(
            ProjectWatcher.isRelevant(path: chapter, flags: directoryFlags(kFSEventStreamEventFlagItemRenamed)))
        XCTAssertFalse(
            ProjectWatcher.isRelevant(path: chapter, flags: directoryFlags(kFSEventStreamEventFlagItemModified)))

        let page = chapter + "/001.jpg"
        XCTAssertTrue(ProjectWatcher.isRelevant(path: page, flags: fileFlags(kFSEventStreamEventFlagItemCreated)))
        XCTAssertFalse(ProjectWatcher.isRelevant(path: page, flags: fileFlags(kFSEventStreamEventFlagItemModified)))

        // Reading a page or an archive touches its access time; that metadata
        // event must not rescan the library.
        let archive = chapter + "/Chapter 1.cbz"
        XCTAssertFalse(
            ProjectWatcher.isRelevant(path: archive, flags: fileFlags(kFSEventStreamEventFlagItemInodeMetaMod)))
        XCTAssertTrue(ProjectWatcher.isRelevant(path: archive, flags: fileFlags(kFSEventStreamEventFlagItemCreated)))
    }

    func testCoalescedAndHiddenEventsAreRelevant() {
        XCTAssertTrue(
            ProjectWatcher.isRelevant(
                path: "/Library/Manga",
                flags: FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
            )
        )
        XCTAssertFalse(
            ProjectWatcher.isRelevant(
                path: "/Library/Manga/__MACOSX/001.jpg",
                flags: fileFlags(kFSEventStreamEventFlagItemCreated)
            )
        )
        XCTAssertFalse(
            ProjectWatcher.isRelevant(
                path: "/Library/Manga/.hidden/001.jpg",
                flags: fileFlags(kFSEventStreamEventFlagItemCreated)
            )
        )
    }

    private func fileFlags(_ flags: Int) -> FSEventStreamEventFlags {
        FSEventStreamEventFlags(flags | kFSEventStreamEventFlagItemIsFile)
    }

    private func directoryFlags(_ flags: Int) -> FSEventStreamEventFlags {
        FSEventStreamEventFlags(flags | kFSEventStreamEventFlagItemIsDir)
    }

    private func openDescriptorCount() -> Int {
        let size = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return 0 }
        return Int(size) / MemoryLayout<proc_fdinfo>.stride
    }
}
