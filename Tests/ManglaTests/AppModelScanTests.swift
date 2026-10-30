import Foundation
import XCTest

@testable import Mangla

final class AppModelScanTests: XCTestCase {
    @MainActor
    func testFailedScanMarksCollectionUnavailable() async {
        let model = AppModel()
        model.persistenceEnabled = false

        let id = UUID()
        model.collections = [
            MangaCollection(
                id: id,
                name: "Missing",
                directoryURL: URL(fileURLWithPath: "/tmp/mangla-missing-\(UUID().uuidString)"),
                mangas: [],
                isAvailable: true,
                lastMangaID: nil,
                bookmark: nil
            )
        ]
        model.selectedCollectionID = id

        model.scan(collectionID: id)
        await model.waitForScans()

        XCTAssertFalse(model.collections[0].isAvailable)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isScanning)
    }
}
