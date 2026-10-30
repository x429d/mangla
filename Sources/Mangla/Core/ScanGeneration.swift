import Foundation

/// Tracks which scan owns a collection. Filesystem walks cannot be interrupted
/// synchronously, so a cancelled walk may finish after a newer one started.
/// Only the generation returned by the latest `begin(for:)` may publish.
struct ScanGeneration: Sendable {
    private var latest: [UUID: Int] = [:]

    mutating func begin(for collectionID: UUID) -> Int {
        let next = (latest[collectionID] ?? 0) + 1
        latest[collectionID] = next
        return next
    }

    mutating func invalidate(_ collectionID: UUID) {
        latest[collectionID, default: 0] += 1
    }

    func isCurrent(_ collectionID: UUID, generation: Int) -> Bool {
        latest[collectionID] == generation
    }
}
