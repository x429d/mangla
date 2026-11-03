import Foundation

/// A chapter together with its position in the manga. The picker shows the
/// original number even while a search filters the list.
struct IndexedChapter: Identifiable, Hashable, Sendable {
    let index: Int
    let chapter: ChapterItem

    var id: String { chapter.id }
}

enum ChapterIndex {
    /// Case-insensitive chapter search. An empty query keeps every chapter.
    static func entries(_ chapters: [ChapterItem], query: String) -> [IndexedChapter] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return chapters.enumerated().compactMap { index, chapter in
            guard trimmed.isEmpty || chapter.title.localizedCaseInsensitiveContains(trimmed) else {
                return nil
            }
            return IndexedChapter(index: index, chapter: chapter)
        }
    }

    static func filter(_ chapters: [ChapterItem], query: String) -> [ChapterItem] {
        entries(chapters, query: query).map(\.chapter)
    }
}

// MARK: - Long chapter menus

/// A slice of a long chapter menu. The card context menu uses these ranges so
/// a manga with hundreds of chapters stays navigable without one enormous
/// popup.
struct ChapterMenuGroup: Identifiable, Hashable, Sendable {
    let id: Int
    /// 1-based chapter numbers shown in the submenu title.
    let lowerBound: Int
    let upperBound: Int
    let chapters: [ChapterItem]
}

enum ChapterMenu {
    static let groupSize = 40

    static func groups(_ chapters: [ChapterItem], size: Int = groupSize) -> [ChapterMenuGroup] {
        guard size > 0, !chapters.isEmpty else { return [] }
        return stride(from: 0, to: chapters.count, by: size).map { start in
            let end = min(start + size, chapters.count)
            return ChapterMenuGroup(
                id: start,
                lowerBound: start + 1,
                upperBound: end,
                chapters: Array(chapters[start..<end])
            )
        }
    }
}
