import CryptoKit
import Foundation
import os

enum ComicArchiveFormat: Sendable, Equatable {
    case zip
    case rar
}

enum ArchiveFormat {
    /// Archives are detected by content, not by extension: plenty of `.cbr`
    /// files in the wild are really ZIPs, and `.cbz` files are occasionally
    /// RARs.
    static func detect(url: URL) throws -> ComicArchiveFormat {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ArchiveError.unreadable(url)
        }
        defer { try? handle.close() }

        let header: Data
        do {
            header = try handle.read(upToCount: 8) ?? Data()
        } catch {
            throw ArchiveError.unreadable(url)
        }

        let magic = [UInt8](header)
        if magic.count >= 2, magic[0] == 0x50, magic[1] == 0x4B {
            return .zip
        }
        let rarMagic: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]
        if magic.count >= rarMagic.count, Array(magic.prefix(rarMagic.count)) == rarMagic {
            return .rar
        }
        throw ArchiveError.notAnArchive(url)
    }
}

/// Cached archive listings. The scanner runs synchronously on a detached task,
/// so this small cache uses a lock instead of an actor.
enum ArchiveListing {
    private static let logger = Logger(subsystem: "com.mangla.reader", category: "archive")
    private static let cache = OSAllocatedUnfairLock(initialState: [String: [String]]())
    private static let cacheLimit = 256

    /// Image entries inside an archive, sorted the same way as folder pages.
    static func imageEntries(for url: URL) throws -> [String] {
        let key = cacheKey(for: url)
        if let cached = cache.withLock({ $0[key] }) { return cached }

        let format = try ArchiveFormat.detect(url: url)
        let rawEntries: [String]
        switch format {
        case .zip:
            let archive = try ZipArchive(url: url)
            let imageEntries = archive.entries.values.filter {
                PageFormat.isImageEntry($0.path)
            }
            if !imageEntries.isEmpty, imageEntries.allSatisfy({ $0.flags & 0x0001 != 0 }) {
                throw ArchiveError.encrypted(url)
            }
            rawEntries = imageEntries.map(\.path)
        case .rar:
            guard RarTool.isAvailable else { throw ArchiveError.toolUnavailable }
            rawEntries = try RarTool.list(url: url)
        }

        let images =
            rawEntries
            .filter { PageFormat.isImageEntry($0) }
            .sorted(by: PageFormat.pageOrder)

        if images.isEmpty {
            logger.warning("No image entries in \(url.path, privacy: .public)")
        }

        cache.withLock { state in
            if state.count >= cacheLimit { state.removeAll() }
            state[key] = images
        }
        return images
    }

    /// Listing cache key: an archive that changes gets a new key, so stale
    /// entries fall out of use on their own.
    static func cacheKey(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? 0
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(url.standardizedFileURL.path)|\(size)|\(modified)"
    }
}

/// Owns the on-disk extraction cache for RAR archives. ZIP entries are
/// inflated on demand, so only CBR files need a directory.
actor ArchiveStore {
    static let shared = ArchiveStore()

    private static let logger = Logger(subsystem: "com.mangla.reader", category: "archive")
    private static let readyMarker = ".mangla-ready"
    private static let maxCacheBytes: Int64 = 2 * 1024 * 1024 * 1024
    private static let maxCacheAge: TimeInterval = 14 * 24 * 60 * 60

    private var formats: [String: ComicArchiveFormat] = [:]
    private var zipArchives: [String: ZipArchive] = [:]
    private let zipArchiveLimit = 32
    private let formatLimit = 256
    private var extractions: [String: Task<Void, Error>] = [:]

    // MARK: - Reading

    func imageData(for source: PageSource) throws -> Data {
        guard case .archiveEntry(let archiveURL, let entry) = source else {
            throw ArchiveError.entryMissing(source.containerURL, source.displayName)
        }

        switch try format(for: archiveURL) {
        case .zip:
            let key = ArchiveListing.cacheKey(for: archiveURL)
            if let cached = zipArchives[key] {
                return try cached.data(for: entry)
            }
            let archive = try ZipArchive(url: archiveURL)
            if zipArchives.count >= zipArchiveLimit { zipArchives.removeAll() }
            zipArchives[key] = archive
            return try archive.data(for: entry)
        case .rar:
            if let file = extractedFile(for: archiveURL, entry: entry) {
                do {
                    return try Data(contentsOf: file)
                } catch {
                    Self.logger.warning(
                        "Could not read extracted \(entry, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            return try RarTool.data(url: archiveURL, entry: entry)
        }
    }

    /// Extracts every RAR that owns one of the given pages. Reading a chapter
    /// probes all page sizes, so one batch extraction is much cheaper than one
    /// `bsdtar` process per page.
    func prepare(_ sources: [PageSource]) async {
        var archives: Set<URL> = []
        for source in sources {
            guard case .archiveEntry(let archiveURL, _) = source else { continue }
            guard let format = try? format(for: archiveURL), format == .rar else { continue }
            archives.insert(archiveURL.standardizedFileURL)
        }

        for archiveURL in archives {
            let key = Self.storageKey(for: archiveURL)
            if Self.isPrepared(key: key) { continue }
            let task = extractionTask(for: archiveURL, key: key)
            do {
                try await task.value
            } catch {
                Self.logger.error(
                    "Could not extract \(archiveURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                extractions[key] = nil
            }
        }
    }

    private func format(for url: URL) throws -> ComicArchiveFormat {
        let key = ArchiveListing.cacheKey(for: url)
        if let cached = formats[key] { return cached }
        let format = try ArchiveFormat.detect(url: url)
        if formats.count >= formatLimit { formats.removeAll() }
        formats[key] = format
        return format
    }

    private func extractionTask(for url: URL, key: String) -> Task<Void, Error> {
        if let existing = extractions[key] { return existing }
        let task = Task.detached(priority: .utility) {
            try Self.extract(url: url, key: key)
        }
        extractions[key] = task
        return task
    }

    private func extractedFile(for archiveURL: URL, entry: String) -> URL? {
        guard let root = Self.cacheRoot() else { return nil }
        let directory = root.appendingPathComponent(Self.storageKey(for: archiveURL), isDirectory: true)
        guard Self.isPrepared(directory: directory) else { return nil }

        let file = directory.appendingPathComponent(entry)
        let standardized = file.standardizedFileURL.path
        let prefix = directory.standardizedFileURL.path + "/"
        guard standardized.hasPrefix(prefix) else { return nil }
        guard FileManager.default.fileExists(atPath: standardized) else { return nil }
        return URL(fileURLWithPath: standardized)
    }

    // MARK: - Extraction

    private nonisolated static func extract(url: URL, key: String) throws {
        guard let root = cacheRoot() else { throw ArchiveError.unreadable(url) }
        let destination = root.appendingPathComponent(key, isDirectory: true)
        if isPrepared(directory: destination) { return }

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw ArchiveError.unreadable(url)
        }

        let temporary = root.appendingPathComponent(
            ".extract-\(key)-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            try RarTool.extractAll(url: url, to: temporary)
            try validateExtractedTree(temporary, archiveURL: url)
            try Data().write(to: temporary.appendingPathComponent(readyMarker))
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }

        pruneCacheIfNeeded()
    }

    /// A malicious archive could try to escape the extraction folder through
    /// symlinks or `..` entries. libarchive already strips parent traversal,
    /// and symlinks are removed before the cache is published so a later page
    /// load can never follow one out of the cache.
    private nonisolated static func validateExtractedTree(_ directory: URL, archiveURL: URL) throws {
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
                options: []
            )
        else {
            throw ArchiveError.unreadable(archiveURL)
        }
        let prefix = directory.standardizedFileURL.path + "/"
        var symlinks: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.standardizedFileURL.path.hasPrefix(prefix) else {
                throw ArchiveError.corrupt(archiveURL)
            }
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                symlinks.append(url)
            }
        }
        for symlink in symlinks {
            logger.warning(
                "Removed symlink \(symlink.lastPathComponent, privacy: .public) from \(archiveURL.lastPathComponent, privacy: .public)"
            )
            try? FileManager.default.removeItem(at: symlink)
        }
    }

    private nonisolated static func isPrepared(key: String) -> Bool {
        guard let root = cacheRoot() else { return false }
        return isPrepared(directory: root.appendingPathComponent(key, isDirectory: true))
    }

    private nonisolated static func isPrepared(directory: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(readyMarker).path
        )
    }

    // MARK: - Cache housekeeping

    /// Directory name for an archive. A hash keeps the path short and avoids
    /// putting slashes or colons from the archive path into the cache tree.
    private nonisolated static func storageKey(for url: URL) -> String {
        let identity = ArchiveListing.cacheKey(for: url)
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func cacheRoot() -> URL? {
        guard
            let base = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first
        else { return nil }
        return base.appendingPathComponent("Mangla/Archives", isDirectory: true)
    }

    /// Removes abandoned extraction directories and keeps the cache bounded.
    /// Called on launch and after every successful extraction.
    nonisolated static func pruneCacheIfNeeded() {
        guard let root = cacheRoot() else { return }
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: keys,
                options: []
            )
        else { return }

        let now = Date()
        var directories: [(url: URL, bytes: Int64, modified: Date)] = []
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                continue
            }
            let modified =
                (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? now
            if now.timeIntervalSince(modified) > maxCacheAge {
                try? FileManager.default.removeItem(at: entry)
                continue
            }
            directories.append((entry, directorySize(entry), modified))
        }

        var total = directories.reduce(Int64(0)) { $0 + $1.bytes }
        guard total > maxCacheBytes else { return }
        for directory in directories.sorted(by: { $0.modified < $1.modified }) {
            guard total > maxCacheBytes else { break }
            try? FileManager.default.removeItem(at: directory.url)
            total -= directory.bytes
        }
    }

    private nonisolated static func directorySize(_ url: URL) -> Int64 {
        guard
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        else { return 0 }
        var total: Int64 = 0
        while let file = enumerator.nextObject() as? URL {
            if let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
