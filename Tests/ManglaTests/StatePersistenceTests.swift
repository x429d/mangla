import Foundation
import XCTest

@testable import Mangla

final class StatePersistenceTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ManglaStateTests-\(UUID().uuidString)", isDirectory: true)

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testMissingStateReturnsNil() {
        let store = StateStore(directoryURL: directory)
        XCTAssertNil(store.load())
    }

    func testWriteKeepsPreviousStateAsBackup() throws {
        let store = StateStore(directoryURL: directory)
        try store.write(state(named: "First"))
        try store.write(state(named: "Second"))

        let current = try XCTUnwrap(StatePersistence.decode(Data(contentsOf: store.stateURL)))
        XCTAssertEqual(current.collections.first?.name, "Second")

        let backup = try XCTUnwrap(StatePersistence.decode(Data(contentsOf: store.backupURL)))
        XCTAssertEqual(backup.collections.first?.name, "First")
    }

    func testMissingPrimaryIsRestoredFromBackup() throws {
        let store = StateStore(directoryURL: directory)
        try store.write(state(named: "First"))
        try store.write(state(named: "Second"))
        try FileManager.default.removeItem(at: store.stateURL)

        let restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored.collections.first?.name, "First")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.stateURL.path))
    }

    func testCorruptStateIsQuarantinedAndBackupIsRestored() throws {
        let store = StateStore(directoryURL: directory)
        try store.write(state(named: "First"))
        try store.write(state(named: "Second"))
        try Data("not json".utf8).write(to: store.stateURL)

        let recovered = try XCTUnwrap(store.load())
        XCTAssertEqual(recovered.collections.first?.name, "First")

        let restored = try XCTUnwrap(StatePersistence.decode(Data(contentsOf: store.stateURL)))
        XCTAssertEqual(restored.collections.first?.name, "First")

        let quarantined = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("state.json.corrupt-") }
        XCTAssertEqual(quarantined.count, 1)
    }

    func testCorruptStateWithoutBackupIsPreserved() throws {
        let store = StateStore(directoryURL: directory)
        try Data("{".utf8).write(to: store.stateURL)

        XCTAssertNil(store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.stateURL.path))

        let quarantined = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("state.json.corrupt-") }
        XCTAssertEqual(quarantined.count, 1)
    }

    func testBookmarkRoundTripResolvesTheFolder() throws {
        let folder = directory.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let data = try XCTUnwrap(SecurityBookmark.make(for: folder))
        let resolved = try XCTUnwrap(SecurityBookmark.resolveDetailed(data))

        XCTAssertEqual(resolved.url.standardizedFileURL.path, folder.standardizedFileURL.path)
        XCTAssertFalse(resolved.isStale)
    }

    private func state(named name: String) -> LibraryState {
        let id = UUID()
        return LibraryState(
            collections: [
                StoredCollection(
                    id: id,
                    name: name,
                    path: "/tmp/\(name)",
                    bookmark: nil,
                    lastMangaID: nil
                )
            ],
            selectedCollectionID: id,
            progress: [id.uuidString: [:]]
        )
    }
}
