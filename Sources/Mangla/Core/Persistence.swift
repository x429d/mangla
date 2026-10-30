import Foundation
import os

// MARK: - Persisted collection

struct StoredCollection: Codable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var path: String
    var bookmark: Data?
    var lastMangaID: String?
}

// MARK: - On-disk library state (v2)

struct LibraryState: Codable, Sendable {
    var version: Int
    var collections: [StoredCollection]
    var selectedCollectionID: UUID?
    /// Keyed by collection UUID string, then by manga folder path.
    var progress: [String: [String: MangaProgress]]
    var updatedAt: Date

    init(
        version: Int = 2,
        collections: [StoredCollection] = [],
        selectedCollectionID: UUID? = nil,
        progress: [String: [String: MangaProgress]] = [:],
        updatedAt: Date = .now
    ) {
        self.version = version
        self.collections = collections
        self.selectedCollectionID = selectedCollectionID
        self.progress = progress
        self.updatedAt = updatedAt
    }
}

/// State written by Mangla 1.x (one project, flat progress map).
struct LegacyLibraryState: Codable, Sendable {
    var version: Int?
    var projectPath: String?
    var lastMangaID: String?
    var progress: [String: MangaProgress]?
    var updatedAt: Date?
}

extension LegacyLibraryState {
    func migrated() -> LibraryState? {
        guard let projectPath, !projectPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: projectPath)
        let id = UUID()
        let record = StoredCollection(
            id: id,
            name: url.lastPathComponent,
            path: projectPath,
            bookmark: nil,
            lastMangaID: lastMangaID
        )
        return LibraryState(
            collections: [record],
            selectedCollectionID: id,
            progress: [id.uuidString: progress ?? [:]]
        )
    }
}

/// Reads and writes the library state together with a last-known-good backup.
///
/// A corrupt or unreadable `state.json` is moved aside before the app can write
/// a fresh one, so recovery never silently destroys the user's progress.
struct StateStore: Sendable {
    let directoryURL: URL

    var stateURL: URL { directoryURL.appendingPathComponent("state.json") }
    var backupURL: URL { directoryURL.appendingPathComponent("state.json.bak") }

    func load() -> LibraryState? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: stateURL.path) else { return nil }

        if let data = try? Data(contentsOf: stateURL),
            let state = StatePersistence.decode(data)
        {
            return state
        }

        StatePersistence.logger.error("state.json could not be decoded; attempting backup")
        quarantineCorruptState()

        guard let backupData = try? Data(contentsOf: backupURL),
            let backup = StatePersistence.decode(backupData)
        else {
            StatePersistence.logger.error("state.json.bak is missing or unreadable")
            return nil
        }

        do {
            try backupData.write(to: stateURL, options: [.atomic])
            StatePersistence.logger.notice("Restored state.json from state.json.bak")
        } catch {
            StatePersistence.logger.error("Could not restore state.json from backup: \(error.localizedDescription)")
        }
        return backup
    }

    func write(_ state: LibraryState) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try StatePersistence.encode(state)

        // Keep the previous good file as a fallback. The primary file is only
        // replaced atomically below, so a crash here leaves a valid state.json.
        if fileManager.fileExists(atPath: stateURL.path),
            let existing = try? Data(contentsOf: stateURL),
            StatePersistence.decode(existing) != nil
        {
            do {
                if fileManager.fileExists(atPath: backupURL.path) {
                    try fileManager.removeItem(at: backupURL)
                }
                try fileManager.copyItem(at: stateURL, to: backupURL)
            } catch {
                StatePersistence.logger.error("Could not refresh state.json.bak: \(error.localizedDescription)")
            }
        }

        try data.write(to: stateURL, options: [.atomic])
    }

    private func quarantineCorruptState() {
        let destination = directoryURL.appendingPathComponent(
            "state.json.corrupt-\(Int(Date().timeIntervalSince1970))"
        )
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: stateURL, to: destination)
            StatePersistence.logger.notice("Moved unreadable state.json to \(destination.lastPathComponent)")
        } catch {
            StatePersistence.logger.error("Could not preserve unreadable state.json: \(error.localizedDescription)")
        }
    }
}

enum StatePersistence {
    static let logger = Logger(subsystem: "com.mangla.reader", category: "state")

    static var directoryURL: URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Mangla", isDirectory: true)
    }

    static var stateURL: URL {
        directoryURL.appendingPathComponent("state.json")
    }

    static var store: StateStore {
        StateStore(directoryURL: directoryURL)
    }

    static func load() -> LibraryState? {
        store.load()
    }

    static func decode(_ data: Data) -> LibraryState? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let state = try? decoder.decode(LibraryState.self, from: data), state.version >= 2 {
            return state
        }
        if let legacy = try? decoder.decode(LegacyLibraryState.self, from: data) {
            return legacy.migrated()
        }
        return nil
    }

    static func encode(_ state: LibraryState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(state)
    }

    /// All writes go through one serial queue, so an older snapshot can never
    /// overwrite a newer one (including a synchronous write at termination).
    private static let writeQueue = DispatchQueue(label: "com.mangla.state", qos: .utility)

    static func saveQueued(_ state: LibraryState) {
        writeQueue.async {
            do {
                try store.write(state)
            } catch {
                logger.error("Could not save library state: \(error.localizedDescription)")
            }
        }
    }

    static func saveSynchronously(_ state: LibraryState) {
        writeQueue.sync {
            do {
                try store.write(state)
            } catch {
                logger.error("Could not save library state: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Shared preferences domain

enum AppDefaults {
    static let suiteName = "com.mangla.reader"

    static var shared: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}

// MARK: - Security-scoped bookmarks

struct ResolvedBookmark: Sendable {
    let url: URL
    let isStale: Bool
}

enum SecurityBookmark {
    private static let logger = Logger(subsystem: "com.mangla.reader", category: "bookmarks")

    static func make(for url: URL) -> Data? {
        // Sandboxed apps need the security scope; for a non-sandboxed build
        // creation may fail, so fall back to a regular bookmark.
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            logger.debug(
                "Security-scoped bookmark failed for \(url.path, privacy: .public): \(error.localizedDescription)")
        }

        do {
            return try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            logger.error("Could not create bookmark for \(url.path, privacy: .public): \(error.localizedDescription)")
            return nil
        }
    }

    static func resolve(_ data: Data) -> URL? {
        resolveDetailed(data)?.url
    }

    static func resolveDetailed(_ data: Data) -> ResolvedBookmark? {
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), FileManager.default.fileExists(atPath: url.path) {
            return ResolvedBookmark(url: url, isStale: isStale)
        }

        isStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), FileManager.default.fileExists(atPath: url.path) {
            return ResolvedBookmark(url: url, isStale: isStale)
        }
        return nil
    }
}

/// Reads the single-project bookmark written by Mangla 1.x.
enum LegacyWorkspaceBookmark {
    private static let bookmarkKey = "mangla.workspace.bookmark"
    private static let pathKey = "mangla.workspace.path"

    static func resolveSaved() -> URL? {
        let defaults = AppDefaults.shared
        if let data = defaults.data(forKey: bookmarkKey), let url = SecurityBookmark.resolve(data) {
            return url
        }
        if let path = defaults.string(forKey: pathKey) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}

// MARK: - Reader preferences

enum ReaderPreferences {
    private static let layoutKey = "mangla.reader.layout"
    private static let fitKey = "mangla.reader.fit"
    private static let directionKey = "mangla.reader.direction"

    static var layoutMode: LayoutMode {
        get {
            guard let raw = AppDefaults.shared.string(forKey: layoutKey),
                let value = LayoutMode(rawValue: raw)
            else { return .single }
            return value
        }
        set { AppDefaults.shared.set(newValue.rawValue, forKey: layoutKey) }
    }

    static var fitMode: FitMode {
        get {
            guard let raw = AppDefaults.shared.string(forKey: fitKey),
                let value = FitMode(rawValue: raw)
            else { return .fitHeight }
            return value
        }
        set { AppDefaults.shared.set(newValue.rawValue, forKey: fitKey) }
    }

    static var direction: ReadingDirection {
        get {
            guard let raw = AppDefaults.shared.string(forKey: directionKey),
                let value = ReadingDirection(rawValue: raw)
            else { return .rtl }
            return value
        }
        set { AppDefaults.shared.set(newValue.rawValue, forKey: directionKey) }
    }
}
