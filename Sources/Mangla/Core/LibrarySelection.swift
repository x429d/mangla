import Foundation

enum LibraryMoveDirection: Sendable {
    case left
    case right
    case up
    case down
}

/// Pure selection movement for the library grid. The view reports how many
/// columns are visible, so up/down move by one row on any window width.
enum LibrarySelection {
    static func move(
        from currentID: String?,
        direction: LibraryMoveDirection,
        mangas: [MangaItem],
        columns: Int
    ) -> String? {
        guard !mangas.isEmpty else { return nil }
        guard let currentID, let current = mangas.firstIndex(where: { $0.id == currentID }) else {
            return mangas.first?.id
        }

        let step: Int
        switch direction {
        case .left: step = -1
        case .right: step = 1
        case .up: step = -max(columns, 1)
        case .down: step = max(columns, 1)
        }

        let target = min(max(current + step, 0), mangas.count - 1)
        return mangas[target].id
    }
}
