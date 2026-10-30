import XCTest

@testable import Mangla

final class ScanGenerationTests: XCTestCase {
    func testOnlyTheLatestScanIsCurrent() {
        var generations = ScanGeneration()
        let collection = UUID()

        let first = generations.begin(for: collection)
        let second = generations.begin(for: collection)

        XCTAssertFalse(generations.isCurrent(collection, generation: first))
        XCTAssertTrue(generations.isCurrent(collection, generation: second))
    }

    func testInvalidatedCollectionRejectsItsRunningScan() {
        var generations = ScanGeneration()
        let collection = UUID()

        let running = generations.begin(for: collection)
        generations.invalidate(collection)

        XCTAssertFalse(generations.isCurrent(collection, generation: running))
    }

    func testCollectionsAreIndependent() {
        var generations = ScanGeneration()
        let first = UUID()
        let second = UUID()

        let firstScan = generations.begin(for: first)
        _ = generations.begin(for: second)

        XCTAssertTrue(generations.isCurrent(first, generation: firstScan))
    }
}
