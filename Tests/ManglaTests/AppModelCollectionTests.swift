import XCTest

@testable import Mangla

final class AppModelCollectionTests: XCTestCase {
    @MainActor
    func testProgressIsScopedPerCollection() {
        let model = AppModel()
        let firstID = UUID()
        let secondID = UUID()

        model.collections = [
            MangaCollection(
                id: firstID,
                name: "First",
                directoryURL: URL(fileURLWithPath: "/tmp/ManglaFirst"),
                mangas: [],
                isAvailable: true,
                lastMangaID: nil,
                bookmark: nil
            ),
            MangaCollection(
                id: secondID,
                name: "Second",
                directoryURL: URL(fileURLWithPath: "/tmp/ManglaSecond"),
                mangas: [],
                isAvailable: true,
                lastMangaID: nil,
                bookmark: nil
            ),
        ]

        model.selectedCollectionID = firstID
        model.progress["Berserk"] = MangaProgress()
        XCTAssertNotNil(model.progress["Berserk"])

        model.selectedCollectionID = secondID
        XCTAssertNil(model.progress["Berserk"])

        model.progress["Berserk"] = MangaProgress()
        model.selectedCollectionID = firstID
        XCTAssertNotNil(model.progress["Berserk"])
    }
}
