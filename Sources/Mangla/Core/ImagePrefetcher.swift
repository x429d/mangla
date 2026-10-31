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

    private let cache = NSCache<NSString, CGImage>()
    private let decodeGate = DecodeGate(limit: 2)
    private var loadTasks: [String: Task<CGImage, Error>] = [:]
    private var speculativeTasks: [String: SpeculativeEntry] = [:]
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

    func image(for source: PageSource, quality: PageRenderQuality = .standard) async throws -> CGImage {
        let key = Self.key(for: source, quality: quality)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        if let existing = loadTasks[key] {
            return try await existing.value
        }

        let currentEpoch = epoch

        if let speculative = speculativeTasks.removeValue(forKey: key) {
            loadTasks[key] = speculative.task
            do {
                let image = try await speculative.task.value
                store(image, for: key, epoch: currentEpoch)
                loadTasks[key] = nil
                return image
            } catch {
                loadTasks[key] = nil
                throw error
            }
        }

        let task = Self.makeDecodeTask(
            source: source,
            quality: quality,
            priority: .userInitiated,
            gate: decodeGate
        )
        loadTasks[key] = task
        do {
            let image = try await task.value
            store(image, for: key, epoch: currentEpoch)
            loadTasks[key] = nil
            return image
        } catch {
            loadTasks[key] = nil
            throw error
        }
    }

    func cachedImage(for source: PageSource, quality: PageRenderQuality = .standard) -> CGImage? {
        cache.object(forKey: Self.key(for: source, quality: quality) as NSString)
    }

    // MARK: - Prefetch window

    /// Declares the complete set of pages worth having in memory. Speculative
    /// decodes outside of this set are cancelled; missing ones are started.
    func updatePrefetchWindow(_ sources: [PageSource]) {
        let wanted = Set(sources.map { Self.key(for: $0, quality: .standard) })

        for (key, entry) in speculativeTasks where !wanted.contains(key) {
            entry.task.cancel()
            speculativeTasks[key] = nil
        }

        for source in sources {
            let key = Self.key(for: source, quality: .standard)
            if cache.object(forKey: key as NSString) != nil { continue }
            if loadTasks[key] != nil || speculativeTasks[key] != nil { continue }

            let id = UUID()
            let task = Self.makeDecodeTask(
                source: source,
                quality: .standard,
                priority: .utility,
                gate: decodeGate
            )
            speculativeTasks[key] = SpeculativeEntry(id: id, task: task)

            Task { [weak self] in
                let image = try? await task.value
                await self?.finishSpeculative(key: key, id: id, image: image)
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

    /// Page identity. Only rendered pages (PDFs) depend on the detail level;
    /// image files and archive entries are decoded at their native size.
    private nonisolated static func key(
        for source: PageSource,
        quality: PageRenderQuality
    ) -> String {
        guard source.isPDF else { return source.cacheKey }
        return "\(source.cacheKey)|\(quality.cacheSuffix)"
    }

    private func finishSpeculative(key: String, id: UUID, image: CGImage?) {
        guard let entry = speculativeTasks[key], entry.id == id else { return }
        let currentEpoch = epoch
        speculativeTasks[key] = nil
        if let image {
            store(image, for: key, epoch: currentEpoch)
        }
    }

    private func store(_ image: CGImage, for key: String, epoch: Int) {
        guard epoch == self.epoch else { return }
        cache.setObject(image, forKey: key as NSString, cost: image.bytesPerRow * image.height)
    }

    private nonisolated static func makeDecodeTask(
        source: PageSource,
        quality: PageRenderQuality,
        priority: TaskPriority,
        gate: DecodeGate
    ) -> Task<CGImage, Error> {
        Task.detached(priority: priority) {
            try Task.checkCancellation()
            await gate.acquire()
            do {
                try Task.checkCancellation()
                let image = try await PageImageLoader.image(for: source, quality: quality)
                await gate.release()
                return image
            } catch {
                await gate.release()
                throw error
            }
        }
    }
}
