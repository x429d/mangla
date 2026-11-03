import Foundation

/// Pure ordering for the library grid. The caller filters first, then sorts,
/// so pagination always sees the same stable list.
enum LibraryOrdering {
    static func sorted(
        _ mangas: [MangaItem],
        by sort: LibrarySort,
        progress: [String: MangaProgress]
    ) -> [MangaItem] {
        switch sort {
        case .name:
            return mangas.sorted(by: titleOrder)
        case .recent:
            return mangas.sorted { lhs, rhs in
                let left = progress[lhs.id]?.updatedAt ?? .distantPast
                let right = progress[rhs.id]?.updatedAt ?? .distantPast
                if left != right { return left > right }
                return titleOrder(lhs, rhs)
            }
        case .chapterCount:
            return mangas.sorted { lhs, rhs in
                if lhs.chapterCount != rhs.chapterCount {
                    return lhs.chapterCount > rhs.chapterCount
                }
                return titleOrder(lhs, rhs)
            }
        case .dateAdded:
            return mangas.sorted { lhs, rhs in
                let left = lhs.addedAt ?? .distantPast
                let right = rhs.addedAt ?? .distantPast
                if left != right { return left > right }
                return titleOrder(lhs, rhs)
            }
        }
    }

    private static func titleOrder(_ lhs: MangaItem, _ rhs: MangaItem) -> Bool {
        let order = lhs.title.localizedStandardCompare(rhs.title)
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.id < rhs.id
    }
}
