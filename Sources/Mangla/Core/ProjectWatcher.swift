import Darwin
import Foundation

/// Lightweight recursive-ish directory watcher built on
/// `DispatchSourceFileSystemObject`. One source per project root and per manga
/// folder (capped) detects new chapters and new pages without polling.
@MainActor
final class DirectoryWatcher {
    private let url: URL
    private let onChange: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1

    init?(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.onChange = onChange

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        descriptor = fd

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
        descriptor = -1
    }

    deinit {
        source?.cancel()
    }
}

@MainActor
final class ProjectWatcher {
    private var watchers: [DirectoryWatcher] = []

    init(
        root: URL,
        mangaDirectories: [URL],
        onChange: @escaping @MainActor () -> Void
    ) {
        if let rootWatcher = DirectoryWatcher(url: root, onChange: onChange) {
            watchers.append(rootWatcher)
        }
        // Watching every manga folder keeps chapter additions live. Cap the
        // number of descriptors for very large libraries; the project root
        // watcher (and the manual Refresh button) still work.
        for directory in mangaDirectories.prefix(200) {
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
