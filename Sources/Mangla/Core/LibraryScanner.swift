import Foundation

enum LibraryScanError: LocalizedError {
    case unreadable(URL)
    case notADirectory(URL)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url): "Не удалось прочитать папку \(url.lastPathComponent)"
        case .notADirectory(let url): "\(url.lastPathComponent) не является папкой"
        }
    }
}

/// Recursive, extension-agnostic manga library scanner.
///
/// Supported layouts:
/// ```
/// Project/Manga/001.webp ...              (single chapter)
/// Project/Manga/Chapter 01/001.webp ...   (chapter folders)
/// ```
/// Deeper nesting is supported as well; every folder that directly contains
/// images becomes one chapter, containers are walked recursively.
enum LibraryScanner {
    static let imageExtensions: Set<String> = [
        "webp", "jpg", "jpeg", "png", "avif", "heic"
    ]

    private static let maxDepth = 8
    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .nameKey
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

        let entries = listing(of: root)
        let directImages = entries.filter { isImageFile($0.url) }
        let subdirectories = entries.filter { $0.isDirectory && !$0.isSymlink }

        var mangas: [MangaItem] = []

        // The selected folder may itself be a single manga folder.
        let rootIsManga = !directImages.isEmpty
            && !subdirectories.contains(where: { containsImages(in: $0.url, depth: 0) })

        if rootIsManga {
            if let manga = makeManga(directory: root, projectRoot: root, title: root.lastPathComponent) {
                mangas.append(manga)
            }
        } else {
            for entry in subdirectories {
                guard containsImages(in: entry.url, depth: 0) else { continue }
                if let manga = makeManga(
                    directory: entry.url,
                    projectRoot: root,
                    title: entry.url.lastPathComponent
                ) {
                    mangas.append(manga)
                }
            }
        }

        mangas.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        let name = root.lastPathComponent.isEmpty ? "Коллекция" : root.lastPathComponent
        return ProjectSnapshot(projectURL: root, name: name, mangas: mangas)
    }

    // MARK: - Manga / chapter construction

    private static func makeManga(directory: URL, projectRoot: URL, title: String) -> MangaItem? {
        let mangaID = relativePath(of: directory, from: projectRoot)
        let stableMangaID = mangaID.isEmpty ? "." : mangaID

        let chapters = collectChapters(
            in: directory,
            mangaRoot: directory,
            projectRoot: projectRoot,
            depth: 0
        )
        .filter { !$0.pages.isEmpty }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        guard !chapters.isEmpty else { return nil }

        return MangaItem(
            id: stableMangaID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            directoryURL: directory,
            chapters: chapters
        )
    }

    private static func collectChapters(
        in directory: URL,
        mangaRoot: URL,
        projectRoot: URL,
        depth: Int
    ) -> [ChapterItem] {
        guard depth <= maxDepth else { return [] }

        let entries = listing(of: directory)
        let images = entries
            .filter { isImageFile($0.url) }
            .sorted(by: pageOrder)
        let subdirectories = entries
            .filter { $0.isDirectory && !$0.isSymlink }
            .sorted(by: entryOrder)

        let subdirectoriesWithImages = subdirectories.filter {
            containsImages(in: $0.url, depth: depth + 1)
        }

        // A folder with a handful of images and image subfolders is usually a
        // manga root with a loose cover: treat it as a container. A real
        // chapter folder with many pages and an "extras" subfolder stays a
        // chapter.
        let directoryIsChapter = !images.isEmpty
            && (subdirectoriesWithImages.isEmpty || images.count >= 3)

        if directoryIsChapter {
            let relative = relativePath(of: directory, from: mangaRoot)
            let title = relative.isEmpty ? directory.lastPathComponent : relative
            let chapterID = relativePath(of: directory, from: projectRoot)
            return [
                ChapterItem(
                    id: chapterID.isEmpty ? "." : chapterID,
                    title: title,
                    directoryURL: directory,
                    pages: images.map { PageItem(url: $0.url) }
                )
            ]
        }

        var chapters: [ChapterItem] = []
        for subdirectory in subdirectoriesWithImages {
            chapters.append(contentsOf: collectChapters(
                in: subdirectory.url,
                mangaRoot: mangaRoot,
                projectRoot: projectRoot,
                depth: depth + 1
            ))
        }
        return chapters
    }

    // MARK: - Directory helpers

    private struct Entry {
        let url: URL
        let isDirectory: Bool
        let isSymlink: Bool
    }

    private static func listing(of directory: URL) -> [Entry] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: resourceKeys) else { return nil }
            let name = url.lastPathComponent
            guard !name.hasPrefix("."), name != "__MACOSX" else { return nil }
            return Entry(
                url: url,
                isDirectory: values.isDirectory ?? false,
                isSymlink: values.isSymbolicLink ?? false
            )
        }
    }

    private static func containsImages(in directory: URL, depth: Int) -> Bool {
        guard depth <= 4 else { return false }
        let entries = listing(of: directory)
        if entries.contains(where: { isImageFile($0.url) }) { return true }
        return entries.contains {
            $0.isDirectory && !$0.isSymlink && containsImages(in: $0.url, depth: depth + 1)
        }
    }

    private static func isImageFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard !name.hasPrefix(".") else { return false }
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// Pages are sorted by name *without* the extension, so mixed formats are
    /// interleaved correctly: 1.webp, 2.webp, 3.jpg, 10.jpg, 20.webp.
    private static func pageOrder(_ lhs: Entry, _ rhs: Entry) -> Bool {
        let left = lhs.url.deletingPathExtension().lastPathComponent
        let right = rhs.url.deletingPathExtension().lastPathComponent
        let result = left.localizedStandardCompare(right)
        if result != .orderedSame { return result == .orderedAscending }
        let ext = lhs.url.pathExtension.localizedStandardCompare(rhs.url.pathExtension)
        if ext != .orderedSame { return ext == .orderedAscending }
        return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
    }

    private static func entryOrder(_ lhs: Entry, _ rhs: Entry) -> Bool {
        lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
    }

    static func relativePath(of url: URL, from base: URL) -> String {
        let baseComponents = base.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.count > baseComponents.count,
              Array(components.prefix(baseComponents.count)) == baseComponents else {
            return ""
        }
        return components.dropFirst(baseComponents.count).joined(separator: "/")
    }
}
