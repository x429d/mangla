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
    private let decodeGate = DecodeGate(limit: 2)
    private var loadTasks: [URL: Task<CGImage, Error>] = [:]
    private var speculativeTasks: [URL: SpeculativeEntry] = [:]
    private var epoch = 0

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

        let currentEpoch = epoch

        if let speculative = speculativeTasks.removeValue(forKey: url) {
            loadTasks[url] = speculative.task
            do {
                let image = try await speculative.task.value
                store(image, for: url, epoch: currentEpoch)
                loadTasks[url] = nil
                return image
            } catch {
                loadTasks[url] = nil
                throw error
            }
        }

        let task = Self.makeDecodeTask(url: url, priority: .userInitiated, gate: decodeGate)
        loadTasks[url] = task
        do {
            let image = try await task.value
            store(image, for: url, epoch: currentEpoch)
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
            let task = Self.makeDecodeTask(url: url, priority: .utility, gate: decodeGate)
            speculativeTasks[url] = SpeculativeEntry(id: id, task: task)

            Task { [weak self] in
                let image = try? await task.value
                await self?.finishSpeculative(url: url, id: id, image: image)
            }
        }
    }

    /// Drops every decoded page and stops speculative work. In-flight visible
    /// decodes may still finish, but their results are discarded.
    func releaseMemory() {
        epoch &+= 1
        for entry in speculativeTasks.values { entry.task.cancel() }
        speculativeTasks.removeAll()
        for task in loadTasks.values { task.cancel() }
        loadTasks.removeAll()
        cache.removeAllObjects()
    }

    // MARK: - Private

    private func finishSpeculative(url: URL, id: UUID, image: CGImage?) {
        guard let entry = speculativeTasks[url], entry.id == id else { return }
        let currentEpoch = epoch
        speculativeTasks[url] = nil
        if let image {
            store(image, for: url, epoch: currentEpoch)
        }
    }

    private func store(_ image: CGImage, for url: URL, epoch: Int) {
        guard epoch == self.epoch else { return }
        cache.setObject(image, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
    }

    private nonisolated static func makeDecodeTask(
        url: URL,
        priority: TaskPriority,
        gate: DecodeGate
    ) -> Task<CGImage, Error> {
        Task.detached(priority: priority) {
            try Task.checkCancellation()
            await gate.acquire()
            do {
                try Task.checkCancellation()
                let image = try ImageDecoder.decode(url: url)
                await gate.release()
                return image
            } catch {
                await gate.release()
                throw error
            }
        }
    }
}
