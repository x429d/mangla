import Darwin
import Foundation
import os

/// Lightweight directory watcher built on `DispatchSourceFileSystemObject`.
/// One source per collection root, manga folder, and chapter folder (capped)
/// detects new chapters and new pages without polling.
@MainActor
final class DirectoryWatcher {
    private let onChange: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?

    init?(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: DispatchQueue.global(qos: .utility)
        )
        self.source = source

        source.setEventHandler { @Sendable [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.onChange()
            }
        }
        source.setCancelHandler { @Sendable in
            close(fd)
        }
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit {
        source?.cancel()
    }
}

@MainActor
final class ProjectWatcher {
    private static let logger = Logger(subsystem: "com.mangla.reader", category: "watcher")
    private static let watcherLimit = 200

    private var watchers: [DirectoryWatcher] = []

    init(
        root: URL,
        mangaDirectories: [URL],
        chapterDirectories: [URL],
        onChange: @escaping @MainActor () -> Void
    ) {
        var seen = Set<String>()
        var directories: [URL] = []
        for url in [root] + mangaDirectories + chapterDirectories {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                directories.append(url)
            }
        }

        if directories.count > Self.watcherLimit {
            Self.logger.notice("Watching the first \(Self.watcherLimit) of \(directories.count) directories")
        }

        for directory in directories.prefix(Self.watcherLimit) {
            if let watcher = DirectoryWatcher(url: directory, onChange: onChange) {
                watchers.append(watcher)
            }
        }
    }

    func stop() {
        for watcher in watchers { watcher.stop() }
        watchers.removeAll()
    }
}
