import Foundation

/// Where the pixels of a single page come from.
///
/// A collection can mix plain image folders, comic archives, and PDF files.
/// Everything downstream of the scanner (metadata probe, prefetch cache,
/// reader canvases) addresses pages by `PageSource`, never by a file URL.
enum PageSource: Hashable, Sendable {
    /// An image file inside a folder.
    case imageFile(URL)
    /// An image entry inside a `.cbz`/`.cbr` archive.
    case archiveEntry(archiveURL: URL, entry: String)
    /// A rendered page of a PDF document.
    case pdfPage(pdfURL: URL, pageIndex: Int)

    /// Stable identity for caches and view reuse. Archives and PDFs never
    /// produce a real file URL, so pages are keyed by their container plus an
    /// entry path or page index.
    var cacheKey: String {
        switch self {
        case .imageFile(let url):
            return "file:\(url.standardizedFileURL.path)"
        case .archiveEntry(let archive, let entry):
            return "archive:\(archive.standardizedFileURL.path)#\(entry)"
        case .pdfPage(let pdf, let index):
            return "pdf:\(pdf.standardizedFileURL.path)#\(index)"
        }
    }

    var displayName: String {
        switch self {
        case .imageFile(let url):
            return url.lastPathComponent
        case .archiveEntry(_, let entry):
            return (entry as NSString).lastPathComponent
        case .pdfPage(let pdf, let index):
            return "\(pdf.deletingPathExtension().lastPathComponent) · \(index + 1)"
        }
    }

    var isPDF: Bool {
        if case .pdfPage = self { return true }
        return false
    }

    /// File or archive that owns this page. Used by error reporting.
    var containerURL: URL {
        switch self {
        case .imageFile(let url): return url
        case .archiveEntry(let archive, _): return archive
        case .pdfPage(let pdf, _): return pdf
        }
    }
}

/// Detail level for pages that have to be rendered instead of decoded, such
/// as PDF pages. Image files and archive entries ignore it.
enum PageRenderQuality: String, Hashable, Sendable {
    case standard
    case high

    var cacheSuffix: String { rawValue }
}

/// Formats and naming rules shared by the folder scanner and archive readers.
enum PageFormat {
    static let imageExtensions: Set<String> = [
        "webp", "jpg", "jpeg", "png", "avif", "heic",
    ]

    static let archiveExtensions: Set<String> = ["cbz", "cbr"]
    static let pdfExtensions: Set<String> = ["pdf"]

    static func isImageFile(_ url: URL) -> Bool {
        isImageName(url.lastPathComponent)
    }

    static func isImageName(_ name: String) -> Bool {
        guard !isHiddenName(name) else { return false }
        return imageExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    static func isComicFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return archiveExtensions.contains(ext) || pdfExtensions.contains(ext)
    }

    static func isPDF(_ url: URL) -> Bool {
        pdfExtensions.contains(url.pathExtension.lowercased())
    }

    /// Hidden files, macOS metadata folders, and AppleDouble companions are
    /// never pages, whether they come from a folder or an archive.
    static func isHiddenName(_ name: String) -> Bool {
        guard !name.isEmpty else { return true }
        if name.hasPrefix(".") || name == "__MACOSX" { return true }
        return false
    }

    /// An archive entry is only usable when every path component is visible
    /// and relative. Entries that try to escape the archive are ignored.
    static func isSafeEntryPath(_ path: String) -> Bool {
        let slashed = path.replacingOccurrences(of: "\\", with: "/")
        guard !slashed.hasPrefix("/") else { return false }
        let normalized = normalizedEntryPath(path)
        guard !normalized.isEmpty else { return false }
        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        for component in components {
            if component.isEmpty || component == "." || component == ".." { return false }
            if isHiddenName(String(component)) { return false }
        }
        return true
    }

    /// Archives written on Windows may use backslashes and `./` prefixes.
    static func normalizedEntryPath(_ path: String) -> String {
        var value = path.replacingOccurrences(of: "\\", with: "/")
        while value.hasPrefix("./") {
            value.removeFirst(2)
        }
        while value.hasPrefix("/") {
            value.removeFirst()
        }
        return value
    }

    static func isImageEntry(_ entry: String) -> Bool {
        guard isSafeEntryPath(entry) else { return false }
        let name = (entry as NSString).lastPathComponent
        return isImageName(name)
    }

    /// Pages are sorted by the file name without its extension, so mixed
    /// formats and archive entries interleave the same way: 1, 2, 10, 20.
    static func pageOrder(_ lhs: String, _ rhs: String) -> Bool {
        let leftStem = ((lhs as NSString).lastPathComponent as NSString).deletingPathExtension
        let rightStem = ((rhs as NSString).lastPathComponent as NSString).deletingPathExtension
        let stems = leftStem.localizedStandardCompare(rightStem)
        if stems != .orderedSame { return stems == .orderedAscending }
        let paths = lhs.localizedStandardCompare(rhs)
        if paths != .orderedSame { return paths == .orderedAscending }
        return lhs < rhs
    }
}
