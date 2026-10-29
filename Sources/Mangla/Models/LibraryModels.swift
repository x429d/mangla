import CoreGraphics
import Foundation

// MARK: - Filesystem entities

/// A single image file of a chapter.
struct PageItem: Identifiable, Hashable, Sendable {
    let url: URL

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var fileExtension: String { url.pathExtension.lowercased() }
}

/// A page ready to be rendered. `pixelSize` always holds the *upright* size
/// (EXIF orientation already applied).
struct PageSlot: Identifiable, Hashable, Sendable {
    let url: URL
    let pixelSize: CGSize

    var id: URL { url }
    var aspectRatio: CGFloat {
        guard pixelSize.height > 0 else { return 0.68 }
        return pixelSize.width / pixelSize.height
    }
    var isWide: Bool { pixelSize.width > pixelSize.height * 1.02 }
}

struct ChapterItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let directoryURL: URL
    let pages: [PageItem]

    var pageCount: Int { pages.count }
    var firstPageURL: URL? { pages.first?.url }

    static func == (lhs: ChapterItem, rhs: ChapterItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct MangaItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let directoryURL: URL
    let chapters: [ChapterItem]

    var chapterCount: Int { chapters.count }
    var pageCount: Int { chapters.reduce(0) { $0 + $1.pageCount } }
    var coverURL: URL? { chapters.first?.firstPageURL }

    static func == (lhs: MangaItem, rhs: MangaItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ProjectSnapshot: Sendable {
    let projectURL: URL
    let name: String
    let mangas: [MangaItem]
}

// MARK: - Reading state

enum ReadingStatus: String, Sendable {
    case unread
    case reading
    case completed
}

enum LibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case reading
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Все"
        case .reading: "Читаю"
        case .completed: "Прочитано"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .reading: "book"
        case .completed: "checkmark.circle"
        }
    }
}

struct ChapterProgress: Codable, Hashable, Sendable {
    /// Last page index (0-based) that the reader reached.
    var pageIndex: Int
    var isCompleted: Bool
    var updatedAt: Date

    init(pageIndex: Int, isCompleted: Bool, updatedAt: Date = .now) {
        self.pageIndex = pageIndex
        self.isCompleted = isCompleted
        self.updatedAt = updatedAt
    }
}

struct MangaProgress: Codable, Hashable, Sendable {
    var chapters: [String: ChapterProgress]
    var lastChapterID: String?
    var updatedAt: Date

    init(chapters: [String: ChapterProgress] = [:], lastChapterID: String? = nil, updatedAt: Date = .distantPast) {
        self.chapters = chapters
        self.lastChapterID = lastChapterID
        self.updatedAt = updatedAt
    }
}

// MARK: - Reader preferences

enum LayoutMode: String, CaseIterable, Identifiable, Sendable {
    case single
    case spread
    case webtoon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: "Одна страница"
        case .spread: "Разворот"
        case .webtoon: "Webtoon"
        }
    }

    var symbol: String {
        switch self {
        case .single: "rectangle.portrait"
        case .spread: "rectangle.split.2x1"
        case .webtoon: "rectangle.stack"
        }
    }
}

enum FitMode: String, CaseIterable, Identifiable, Sendable {
    case fitHeight
    case fitWidth
    case original

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fitHeight: "По высоте окна"
        case .fitWidth: "По ширине окна"
        case .original: "Оригинальный размер"
        }
    }

    var shortTitle: String {
        switch self {
        case .fitHeight: "Высота"
        case .fitWidth: "Ширина"
        case .original: "100%"
        }
    }

    var symbol: String {
        switch self {
        case .fitHeight: "arrow.up.and.down"
        case .fitWidth: "arrow.left.and.right"
        case .original: "1.square"
        }
    }
}

enum ReadingDirection: String, CaseIterable, Identifiable, Sendable {
    case ltr
    case rtl

    var id: String { rawValue }
    var title: String { self == .rtl ? "Справа налево" : "Слева направо" }
    var shortTitle: String { self == .rtl ? "RTL" : "LTR" }
}

// MARK: - Geometry helpers

extension CGSize {
    var safeArea: CGFloat { max(width, 1) * max(height, 1) }
    var isUsable: Bool { width.isFinite && height.isFinite && width > 0 && height > 0 }
}

struct ReaderSpread: Identifiable, Hashable, Sendable {
    let id: Int
    let pageIndices: [Int]
}

struct ComputedPageLayout: Sendable {
    let containerSize: CGSize
    let surfaceRect: CGRect
    let pageRects: [CGRect]
    let scale: CGFloat
}
