import CoreGraphics
import Foundation

/// Background decoder + cache for full page images.
///
/// - Decoding runs on detached tasks (never on the main actor).
/// - Speculative prefetches can be cancelled when the reader moves away.
/// - Visible page requests are never cancelled by a prefetch window change;
///   they are *promoted* out of the speculative pool instead.
actor ImagePrefetcher {
    static let shared = ImagePrefetcher()

    private let cache = NSCache<NSURL, CGImage>()
    private var loadTasks: [URL: Task<CGImage, Error>] = [:]
    private var speculativeTasks: [URL: SpeculativeEntry] = [:]

    private struct SpeculativeEntry {
        let id: UUID
        let task: Task<CGImage, Error>
    }

    init() {
        cache.totalCostLimit = 700 * 1024 * 1024
        cache.countLimit = 48
    }

    // MARK: - Visible page request

    func image(for url: URL) async throws -> CGImage {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        if let existing = loadTasks[url] {
            return try await existing.value
        }

        if let speculative = speculativeTasks.removeValue(forKey: url) {
            loadTasks[url] = speculative.task
            do {
                let image = try await speculative.task.value
                store(image, for: url)
                loadTasks[url] = nil
                return image
            } catch {
                loadTasks[url] = nil
                throw error
            }
        }

        let task = Self.makeDecodeTask(url: url, priority: .userInitiated)
        loadTasks[url] = task
        do {
            let image = try await task.value
            store(image, for: url)
            loadTasks[url] = nil
            return image
        } catch {
            loadTasks[url] = nil
            throw error
        }
    }

    func cachedImage(for url: URL) -> CGImage? {
        cache.object(forKey: url as NSURL)
    }

    // MARK: - Prefetch window

    /// Declares the complete set of pages worth having in memory. Speculative
    /// decodes outside of this set are cancelled; missing ones are started.
    func updatePrefetchWindow(_ urls: [URL]) {
        let wanted = Set(urls)

        for (url, entry) in speculativeTasks where !wanted.contains(url) {
            entry.task.cancel()
            speculativeTasks[url] = nil
        }

        for url in wanted {
            if cache.object(forKey: url as NSURL) != nil { continue }
            if loadTasks[url] != nil || speculativeTasks[url] != nil { continue }

            let id = UUID()
            let task = Self.makeDecodeTask(url: url, priority: .utility)
            speculativeTasks[url] = SpeculativeEntry(id: id, task: task)

            Task { [weak self] in
                let image = try? await task.value
                await self?.finishSpeculative(url: url, id: id, image: image)
            }
        }
    }

    func clearCache() {
        cache.removeAllObjects()
    }

    // MARK: - Private

    private func finishSpeculative(url: URL, id: UUID, image: CGImage?) {
        guard let entry = speculativeTasks[url], entry.id == id else { return }
        speculativeTasks[url] = nil
        if let image {
            store(image, for: url)
        }
    }

    private func store(_ image: CGImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
    }

    private nonisolated static func makeDecodeTask(
        url: URL,
        priority: TaskPriority
    ) -> Task<CGImage, Error> {
        Task.detached(priority: priority) {
            try Task.checkCancellation()
            return try ImageDecoder.decode(url: url)
        }
    }
}
