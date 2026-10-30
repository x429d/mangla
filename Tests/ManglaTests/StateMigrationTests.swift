import XCTest

@testable import Mangla

final class StateMigrationTests: XCTestCase {
    func testLegacySingleProjectStateMigratesToOneCollection() throws {
        let progress = MangaProgress(
            chapters: [
                "Berserk/Vol. 01": ChapterProgress(pageIndex: 4, isCompleted: false)
            ],
            lastChapterID: "Berserk/Vol. 01",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let legacy = LegacyLibraryState(
            version: 1,
            projectPath: "/tmp/MangaDemo",
            lastMangaID: "Berserk",
            progress: ["Berserk": progress],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(legacy)

        let state = try XCTUnwrap(StatePersistence.decode(data))
        XCTAssertEqual(state.version, 2)
        XCTAssertEqual(state.collections.count, 1)

        let record = try XCTUnwrap(state.collections.first)
        XCTAssertEqual(record.path, "/tmp/MangaDemo")
        XCTAssertEqual(record.name, "MangaDemo")
        XCTAssertEqual(record.lastMangaID, "Berserk")
        XCTAssertEqual(state.selectedCollectionID, record.id)

        let migrated = try XCTUnwrap(state.progress[record.id.uuidString]?["Berserk"])
        XCTAssertEqual(migrated.lastChapterID, "Berserk/Vol. 01")
        XCTAssertEqual(migrated.chapters["Berserk/Vol. 01"]?.pageIndex, 4)
        XCTAssertEqual(migrated.chapters["Berserk/Vol. 01"]?.isCompleted, false)
    }

    func testMigratedStateRoundTripsWithoutAnotherMigration() throws {
        let legacy = LegacyLibraryState(
            version: 1,
            projectPath: "/tmp/MangaDemo",
            lastMangaID: "Berserk",
            progress: ["Berserk": MangaProgress()],
            updatedAt: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(legacy)
        let migrated = try XCTUnwrap(StatePersistence.decode(data))
        let encoded = try StatePersistence.encode(migrated)
        let decoded = try XCTUnwrap(StatePersistence.decode(encoded))

        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.collections.first?.id, migrated.collections.first?.id)
        XCTAssertEqual(decoded.selectedCollectionID, migrated.selectedCollectionID)
        XCTAssertEqual(decoded.progress.keys, migrated.progress.keys)
    }
}
