import Foundation
import os

enum LibraryScanError: LocalizedError {
    case unreadable(URL)
    case notADirectory(URL)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url): tf(.scanUnreadable, url.lastPathComponent)
        case .notADirectory(let url): tf(.scanNotDirectory, url.lastPathComponent)
        }
    }
}

/// Recursive manga library scanner.
///
/// Supported layouts:
/// ```
/// Project/Manga/001.webp ...              (single chapter)
/// Project/Manga/Chapter 01/001.webp ...   (chapter folders)
/// Project/Manga/Chapter 01.cbz ...        (archive chapters)
/// Project/Manga/Chapter 01.pdf ...        (PDF chapters)
/// Project/One Shot.cbz                    (a loose archive is its own manga)
/// ```
/// A folder that directly contains images is one chapter. Archive and PDF
/// files next to them become chapters named after the file. Deeper nesting is
/// walked up to a fixed depth, and unreadable archives are skipped with a log.
enum LibraryScanner {
    static let imageExtensions = PageFormat.imageExtensions
    static let archiveExtensions = PageFormat.archiveExtensions

    private static let maxDepth = 8
    private static let logger = Logger(subsystem: "com.mangla.reader", category: "scanner")
    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .nameKey,
    ]

    // MARK: - Public API

    static func scan(projectURL: URL) throws -> ProjectSnapshot {
        let root = projectURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            throw LibraryScanError.unreadable(root)
        }
        guard isDirectory.boolValue else {
            throw LibraryScanError.notADirectory(root)
        }

        guard let entries = listing(of: root) else {
            throw LibraryScanError.unreadable(root)
        }
        let directImages = entries.filter { !$0.isDirectory && isImageFile($0.url) }
        let directComics = entries.filter { !$0.isDirectory && isComicFile($0.url) }
        let subdirectories = entries.filter { $0.isDirectory && !$0.isSymlink }
        let contentDirectories = subdirectories.filter { containsPages(in: $0.url, depth: 0) }

        var mangas: [MangaItem] = []

        // The selected folder may itself be a single manga folder or a single
        // archive/PDF. Loose files at the collection root are individual
        // mangas only when the root is a real collection.
        let rootIsManga =
            !directImages.isEmpty
            && contentDirectories.isEmpty

        if rootIsManga {
            if let manga = makeManga(
                container: root,
                projectRoot: root,
                title: root.lastPathComponent
            ) {
                mangas.append(manga)
            }
        } else {
            for entry in contentDirectories {
                if let manga = makeManga(
                    container: entry.url,
                    projectRoot: root,
                    title: entry.url.lastPathComponent
                ) {
                    mangas.append(manga)
                }
            }
            for file in directComics {
                if let manga = makeStandaloneManga(file: file.url, projectRoot: root) {
                    mangas.append(manga)
                }
            }
        }

        mangas.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        let name = root.lastPathComponent
        return ProjectSnapshot(projectURL: root, name: name, mangas: mangas)
    }

    // MARK: - Manga / chapter construction

    private static func makeManga(container: URL, projectRoot: URL, title: String) -> MangaItem? {
        let mangaID = relativePath(of: container, from: projectRoot)
        let stableMangaID = mangaID.isEmpty ? "." : mangaID

        let chapters = collectChapters(
            in: container,
            mangaRoot: container,
            projectRoot: projectRoot,
            depth: 0
        )
        .filter { !$0.pages.isEmpty }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        guard !chapters.isEmpty else { return nil }

        return MangaItem(
            id: stableMangaID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            containerURL: container,
            chapters: chapters
        )
    }

    private static func makeStandaloneManga(file: URL, projectRoot: URL) -> MangaItem? {
        let title = file.deletingPathExtension().lastPathComponent
        guard let chapter = makeComicChapter(file: file, projectRoot: projectRoot, title: title) else {
            return nil
        }
        let mangaID = relativePath(of: file, from: projectRoot)
        return MangaItem(
            id: mangaID.isEmpty ? "." : mangaID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            containerURL: file,
            chapters: [chapter]
        )
    }

    private static func collectChapters(
        in directory: URL,
        mangaRoot: URL,
        projectRoot: URL,
        depth: Int
    ) -> [ChapterItem] {
        guard depth <= maxDepth else {
            logger.warning("Stopped chapter scan at \(directory.path, privacy: .public): depth limit \(maxDepth)")
            return []
        }

        guard let entries = listing(of: directory) else { return [] }
        let images =
            entries
            .filter { !$0.isDirectory && isImageFile($0.url) }
            .sorted(by: pageOrder)
        let comics =
            entries
            .filter { !$0.isDirectory && isComicFile($0.url) }
            .sorted(by: entryOrder)
        let subdirectories =
            entries
            .filter { $0.isDirectory && !$0.isSymlink }
            .sorted(by: entryOrder)

        let subdirectoriesWithPages = subdirectories.filter {
            containsPages(in: $0.url, depth: depth + 1)
        }

        // A folder with a handful of images and image subfolders is usually a
        // manga root with a loose cover: treat it as a container. A real
        // chapter folder with many pages and an "extras" subfolder stays a
        // chapter.
        let directoryIsChapter =
            !images.isEmpty
            && (subdirectoriesWithPages.isEmpty || images.count >= 3)

        var chapters: [ChapterItem] = []

        if directoryIsChapter {
            let relative = relativePath(of: directory, from: mangaRoot)
            let title = relative.isEmpty ? directory.lastPathComponent : relative
            let chapterID = relativePath(of: directory, from: projectRoot)
            chapters.append(
                ChapterItem(
                    id: chapterID.isEmpty ? "." : chapterID,
                    title: title,
                    containerURL: directory,
                    pages: images.map { PageItem(source: .imageFile($0.url)) }
                )
            )
        } else {
            for subdirectory in subdirectoriesWithPages {
                chapters.append(
                    contentsOf: collectChapters(
                        in: subdirectory.url,
                        mangaRoot: mangaRoot,
                        projectRoot: projectRoot,
                        depth: depth + 1
                    ))
            }
        }

        // Archives and PDFs inside a manga folder are chapters of their own,
        // whether or not the folder also holds loose images.
        for comic in comics {
            let relative = relativePath(of: comic.url, from: mangaRoot)
            let title =
                relative.isEmpty
                ? comic.url.deletingPathExtension().lastPathComponent
                : (relative as NSString).deletingPathExtension
            if let chapter = makeComicChapter(
                file: comic.url,
                projectRoot: projectRoot,
                title: title
            ) {
                chapters.append(chapter)
            }
        }

        return chapters
    }

    private static func makeComicChapter(
        file: URL,
        projectRoot: URL,
        title: String
    ) -> ChapterItem? {
        let chapterID = relativePath(of: file, from: projectRoot)
        let pages: [PageItem]

        if PageFormat.isPDF(file) {
            let count = PDFPageReader.pageCount(url: file)
            guard count > 0 else {
                logger.warning("Could not read PDF \(file.path, privacy: .public)")
                return nil
            }
            pages = (0..<count).map {
                PageItem(source: .pdfPage(pdfURL: file, pageIndex: $0))
            }
        } else {
            let entries: [String]
            do {
                entries = try ArchiveListing.imageEntries(for: file)
            } catch {
                logger.warning(
                    "Skipping archive \(file.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
            guard !entries.isEmpty else { return nil }
            pages = entries.map {
                PageItem(source: .archiveEntry(archiveURL: file, entry: $0))
            }
        }

        guard !pages.isEmpty else { return nil }
        return ChapterItem(
            id: chapterID.isEmpty ? "." : chapterID,
            title: title,
            containerURL: file,
            pages: pages
        )
    }

    // MARK: - Directory helpers

    private struct Entry {
        let url: URL
        let isDirectory: Bool
        let isSymlink: Bool
    }

    private static func listing(of directory: URL) -> [Entry]? {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )
        } catch {
            logger.error("Could not list \(directory.path, privacy: .public): \(error.localizedDescription)")
            return nil
        }

        return urls.compactMap { url in
            do {
                let values = try url.resourceValues(forKeys: resourceKeys)
                let name = url.lastPathComponent
                guard !name.hasPrefix("."), name != "__MACOSX" else { return nil }
                return Entry(
                    url: url,
                    isDirectory: values.isDirectory ?? false,
                    isSymlink: values.isSymbolicLink ?? false
                )
            } catch {
                logger.debug(
                    "Could not read attributes for \(url.path, privacy: .public): \(error.localizedDescription)")
                return nil
            }
        }
    }

    private static func containsPages(in directory: URL, depth: Int) -> Bool {
        guard depth <= maxDepth, let entries = listing(of: directory) else { return false }
        if entries.contains(where: { !$0.isDirectory && isPageFile($0.url) }) { return true }
        return entries.contains {
            $0.isDirectory && !$0.isSymlink && containsPages(in: $0.url, depth: depth + 1)
        }
    }

    private static func isImageFile(_ url: URL) -> Bool {
        PageFormat.isImageFile(url)
    }

    private static func isComicFile(_ url: URL) -> Bool {
        PageFormat.isComicFile(url)
    }

    private static func isPageFile(_ url: URL) -> Bool {
        PageFormat.isImageFile(url) || PageFormat.isComicFile(url)
    }

    /// Pages are sorted by name *without* the extension, so mixed formats are
    /// interleaved correctly: 1.webp, 2.webp, 3.jpg, 10.jpg, 20.webp.
    private static func pageOrder(_ lhs: Entry, _ rhs: Entry) -> Bool {
        PageFormat.pageOrder(lhs.url.lastPathComponent, rhs.url.lastPathComponent)
    }

    private static func entryOrder(_ lhs: Entry, _ rhs: Entry) -> Bool {
        lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
    }

    static func relativePath(of url: URL, from base: URL) -> String {
        let baseComponents = base.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.count > baseComponents.count,
            Array(components.prefix(baseComponents.count)) == baseComponents
        else {
            return ""
        }
        return components.dropFirst(baseComponents.count).joined(separator: "/")
    }
}
