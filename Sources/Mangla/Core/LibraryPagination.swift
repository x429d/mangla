import Foundation

/// Pure pagination math for the library grid.
enum LibraryPagination {
    static let defaultPageSize = 30

    static func pageCount(total: Int, pageSize: Int = defaultPageSize) -> Int {
        guard total > 0, pageSize > 0 else { return 1 }
        return (total + pageSize - 1) / pageSize
    }

    static func clampedPage(_ page: Int, total: Int, pageSize: Int = defaultPageSize) -> Int {
        min(max(page, 0), pageCount(total: total, pageSize: pageSize) - 1)
    }

    static func range(total: Int, page: Int, pageSize: Int = defaultPageSize) -> Range<Int> {
        guard total > 0, pageSize > 0 else { return 0..<0 }
        let clamped = clampedPage(page, total: total, pageSize: pageSize)
        let start = clamped * pageSize
        return start..<min(start + pageSize, total)
    }

    static func rangeLabel(total: Int, page: Int, pageSize: Int = defaultPageSize) -> String {
        let range = range(total: total, page: page, pageSize: pageSize)
        guard !range.isEmpty else { return "0 из 0" }
        return "\(range.lowerBound + 1)–\(range.upperBound) из \(total)"
    }
}
