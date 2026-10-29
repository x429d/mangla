import Foundation

// MARK: - On-disk library state

struct LibraryState: Codable, Sendable {
    var version: Int
    var projectPath: String?
    var lastMangaID: String?
    var progress: [String: MangaProgress]
    var updatedAt: Date

    init(
        version: Int = 1,
        projectPath: String? = nil,
        lastMangaID: String? = nil,
        progress: [String: MangaProgress] = [:],
        updatedAt: Date = .now
    ) {
        self.version = version
        self.projectPath = projectPath
        self.lastMangaID = lastMangaID
        self.progress = progress
        self.updatedAt = updatedAt
    }
}

enum StatePersistence {
    static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Mangla", isDirectory: true)
    }

    static var stateURL: URL {
        directoryURL.appendingPathComponent("state.json")
    }

    static func load() -> LibraryState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LibraryState.self, from: data)
    }

    /// All writes go through one serial queue, so an older snapshot can never
    /// overwrite a newer one (including a synchronous write at termination).
    private static let writeQueue = DispatchQueue(label: "com.mangla.state", qos: .utility)

    static func saveQueued(_ state: LibraryState) {
        writeQueue.async {
            try? write(state)
        }
    }

    static func saveSynchronously(_ state: LibraryState) {
        writeQueue.sync {
            try? write(state)
        }
    }

    private static func write(_ state: LibraryState) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: [.atomic])
    }
}

// MARK: - Shared preferences domain

enum AppDefaults {
    static let suiteName = "com.mangla.reader"

    static var shared: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}

// MARK: - Security-scoped workspace bookmark

enum WorkspaceBookmark {
    private static let bookmarkKey = "mangla.workspace.bookmark"
    private static let pathKey = "mangla.workspace.path"

    static func save(_ url: URL) {
        let defaults = AppDefaults.shared
        defaults.set(url.path, forKey: pathKey)
        if let data = makeBookmark(for: url) {
            defaults.set(data, forKey: bookmarkKey)
        } else {
            defaults.removeObject(forKey: bookmarkKey)
        }
    }

    static func resolve() -> URL? {
        let defaults = AppDefaults.shared
        if let data = defaults.data(forKey: bookmarkKey), let url = resolveBookmark(data) {
            return url
        }
        if let path = defaults.string(forKey: pathKey) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    static func clear() {
        let defaults = AppDefaults.shared
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: pathKey)
    }

    private static func makeBookmark(for url: URL) -> Data? {
        // Sandboxed apps need the security scope; for a non-sandboxed SPM binary
        // creation may fail, so fall back to a regular bookmark.
        if let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return data
        }
        return try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        isStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), FileManager.default.fileExists(atPath: url.path) {
            return url
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
                  let value = LayoutMode(rawValue: raw) else { return .single }
            return value
        }
        set { AppDefaults.shared.set(newValue.rawValue, forKey: layoutKey) }
    }

    static var fitMode: FitMode {
        get {
            guard let raw = AppDefaults.shared.string(forKey: fitKey),
                  let value = FitMode(rawValue: raw) else { return .fitHeight }
            return value
        }
        set { AppDefaults.shared.set(newValue.rawValue, forKey: fitKey) }
    }

    static var direction: ReadingDirection {
        get {
            guard let raw = AppDefaults.shared.string(forKey: directionKey),
                  let value = ReadingDirection(rawValue: raw) else { return .rtl }
            return value
        }
        set { AppDefaults.shared.set(newValue.rawValue, forKey: directionKey) }
    }
}
