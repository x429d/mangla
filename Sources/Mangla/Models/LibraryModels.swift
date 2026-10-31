import CoreGraphics
import Foundation

// MARK: - Filesystem entities

/// A single page of a chapter.
struct PageItem: Identifiable, Hashable, Sendable {
    let source: PageSource

    init(source: PageSource) {
        self.source = source
    }

    /// Convenience for folder pages.
    init(url: URL) {
        self.source = .imageFile(url)
    }

    var id: PageSource { source }

    /// Page name without its extension, used by tests and diagnostics.
    var name: String {
        switch source {
        case .imageFile(let url):
            return url.deletingPathExtension().lastPathComponent
        case .archiveEntry(_, let entry):
            let file = (entry as NSString).lastPathComponent
            return (file as NSString).deletingPathExtension
        case .pdfPage(_, let index):
            return "\(index + 1)"
        }
    }

    var fileExtension: String {
        switch source {
        case .imageFile(let url):
            return url.pathExtension.lowercased()
        case .archiveEntry(_, let entry):
            return (entry as NSString).pathExtension.lowercased()
        case .pdfPage:
            return "pdf"
        }
    }
}

/// A page ready to be rendered. `pixelSize` always holds the *upright* size
/// (EXIF orientation already applied).
struct PageSlot: Identifiable, Hashable, Sendable {
    let source: PageSource
    let pixelSize: CGSize

    init(source: PageSource, pixelSize: CGSize) {
        self.source = source
        self.pixelSize = pixelSize
    }

    /// Convenience for folder pages.
    init(url: URL, pixelSize: CGSize) {
        self.init(source: .imageFile(url), pixelSize: pixelSize)
    }

    var id: PageSource { source }
    var aspectRatio: CGFloat {
        guard pixelSize.height > 0 else { return 0.68 }
        return pixelSize.width / pixelSize.height
    }
    var isWide: Bool { pixelSize.width > pixelSize.height * 1.02 }
}

struct ChapterItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Folder or archive/PDF file that owns the chapter.
    let containerURL: URL
    let pages: [PageItem]

    var pageCount: Int { pages.count }
    var firstPageSource: PageSource? { pages.first?.source }

    static func == (lhs: ChapterItem, rhs: ChapterItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct MangaItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Folder, or the archive/PDF file when a single file is its own manga.
    let containerURL: URL
    let chapters: [ChapterItem]

    var chapterCount: Int { chapters.count }
    var pageCount: Int { chapters.reduce(0) { $0 + $1.pageCount } }
    var coverSource: PageSource? { chapters.first?.firstPageSource }

    static func == (lhs: MangaItem, rhs: MangaItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ProjectSnapshot: Sendable {
    let projectURL: URL
    let name: String
    let mangas: [MangaItem]
}

/// A root folder opened in the app. Several collections can be active at once.
struct MangaCollection: Identifiable, Sendable {
    let id: UUID
    var name: String
    var directoryURL: URL
    var mangas: [MangaItem]
    var isAvailable: Bool
    var lastMangaID: String?
    var bookmark: Data?

    var mangaCount: Int { mangas.count }
    var chapterCount: Int { mangas.reduce(0) { $0 + $1.chapterCount } }
    var pageCount: Int { mangas.reduce(0) { $0 + $1.pageCount } }
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
        case .all: t(.filterAll)
        case .reading: t(.filterReading)
        case .completed: t(.filterCompleted)
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
        case .single: t(.layoutSingle)
        case .spread: t(.layoutSpread)
        case .webtoon: t(.layoutWebtoon)
        }
    }

    var symbol: String {
        switch self {
        case .single: "rectangle.portrait"
        case .spread: "rectangle.split.2x1"
        case .webtoon: "rectangle.stack"
        }
    }

    var shortcutKey: String {
        switch self {
        case .single: "1"
        case .spread: "2"
        case .webtoon: "3"
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
        case .fitHeight: t(.fitHeight)
        case .fitWidth: t(.fitWidth)
        case .original: t(.fitOriginal)
        }
    }

    var shortTitle: String {
        switch self {
        case .fitHeight: t(.fitHeightShort)
        case .fitWidth: t(.fitWidthShort)
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

    var shortcutKey: String {
        switch self {
        case .fitHeight: "H"
        case .fitWidth: "W"
        case .original: "O"
        }
    }
}

enum ReadingDirection: String, CaseIterable, Identifiable, Sendable {
    case ltr
    case rtl

    var id: String { rawValue }
    var title: String { self == .rtl ? t(.directionRTL) : t(.directionLTR) }
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
