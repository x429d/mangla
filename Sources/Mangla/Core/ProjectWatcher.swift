import CoreServices
import Foundation
import os

/// Watches a whole collection tree with one FSEvents stream.
///
/// The previous design opened one vnode source per collection root, manga
/// folder, and chapter folder. A large collection easily owns a hundred
/// directories, and macOS hands GUI apps a 256-descriptor soft limit, so a few
/// collections exhausted the process. From then on every `open` failed and
/// thumbnails and pages silently stopped loading. One stream per collection
/// keeps descriptor use flat no matter how many chapters the tree contains.
final class ProjectWatcher {
    private static let logger = Logger(subsystem: "com.mangla.reader", category: "watcher")
    private static let queue = DispatchQueue(label: "com.mangla.reader.fsevents", qos: .utility)

    private let callback: ProjectWatcherCallback
    private var stream: FSEventStreamRef?

    init(root: URL, onChange: @escaping @MainActor () -> Void) {
        self.callback = ProjectWatcherCallback(onChange: onChange)
        start(root: root)
    }

    func stop() {
        callback.stop()
        guard let stream else { return }
        self.stream = nil
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    private func start(root: URL) {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(callback).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagNoDefer
        )

        guard
            let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                Self.eventCallback,
                &context,
                [root.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.25,
                flags
            )
        else {
            Self.logger.error("Could not create a watcher for \(root.path, privacy: .public)")
            return
        }

        FSEventStreamSetDispatchQueue(stream, Self.queue)
        guard FSEventStreamStart(stream) else {
            Self.logger.error("Could not start a watcher for \(root.path, privacy: .public)")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }
        self.stream = stream
    }

    private static let eventCallback: FSEventStreamCallback = {
        _, info, count, eventPaths, eventFlags, _ in
        guard let info, count > 0 else { return }
        let callback = Unmanaged<ProjectWatcherCallback>.fromOpaque(info).takeUnretainedValue()
        guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String], paths.count == count else {
            // Without matching paths the safest move is a rescan, not a guess.
            callback.notify()
            return
        }
        let flags = UnsafeBufferPointer(start: eventFlags, count: count)
        guard zip(paths, flags).contains(where: { isRelevant(path: $0, flags: $1) }) else { return }
        callback.notify()
    }

    /// FSEvents reports file and directory metadata changes as well as
    /// structural ones. Reading a page or an archive updates its access time,
    /// and a directory's own mtime changes whenever a child is touched;
    /// reacting to those events would rescan the library on every page turn.
    /// Only entries that were created, removed, or renamed can change the
    /// library, so everything else is ignored.
    nonisolated static func isRelevant(path: String, flags: FSEventStreamEventFlags) -> Bool {
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0 { return true }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 { return true }

        let structural = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemCreated
                | kFSEventStreamEventFlagItemRemoved
                | kFSEventStreamEventFlagItemRenamed
        )
        guard flags & structural != 0 else { return false }

        let components = URL(fileURLWithPath: path).pathComponents
        return !components.contains { PageFormat.isHiddenName($0) }
    }
}

/// Bridges the C callback, which runs on a background queue, to the main
/// actor. Bursts are coalesced so a scan racing with its own directory reads
/// cannot queue one main-actor task per event.
private final class ProjectWatcherCallback: @unchecked Sendable {
    private struct State {
        var pending = false
        var stopped = false
    }

    private let onChange: @MainActor () -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    nonisolated func notify() {
        let scheduled = state.withLock { state -> Bool in
            if state.pending || state.stopped { return false }
            state.pending = true
            return true
        }
        guard scheduled else { return }

        Task { @MainActor [self] in
            let active = state.withLock { state -> Bool in
                state.pending = false
                return !state.stopped
            }
            guard active else { return }
            onChange()
        }
    }

    nonisolated func stop() {
        state.withLock { $0.stopped = true }
    }
}
