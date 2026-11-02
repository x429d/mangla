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
    private var loadTokens: [String: UUID] = [:]
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

    /// `request` identifies the reader window that owns the decode. A later
    /// request for the same page takes ownership, so a cancellation queued by
    /// the previous window cannot stop the new one.
    func image(
        for source: PageSource,
        quality: PageRenderQuality = .standard,
        request: UUID? = nil
    ) async throws -> CGImage {
        let key = Self.key(for: source, quality: quality)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        if let existing = loadTasks[key] {
            if existing.isCancelled {
                loadTasks[key] = nil
                loadTokens[key] = nil
            } else {
                if let request {
                    loadTokens[key] = request
                }
                let image = try await existing.value
                if let request {
                    finishLoad(key: key, token: request)
                }
                return image
            }
        }

        let token = request ?? UUID()
        let currentEpoch = epoch
        try Task.checkCancellation()

        if let speculative = speculativeTasks.removeValue(forKey: key) {
            loadTasks[key] = speculative.task
            loadTokens[key] = token
            do {
                let image = try await speculative.task.value
                store(image, for: key, epoch: currentEpoch)
                finishLoad(key: key, token: token)
                return image
            } catch {
                finishLoad(key: key, token: token)
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
        loadTokens[key] = token
        do {
            let image = try await task.value
            store(image, for: key, epoch: currentEpoch)
            finishLoad(key: key, token: token)
            return image
        } catch {
            finishLoad(key: key, token: token)
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
        // A replaced window is cancelled from the canvas, but its actor call
        // may already be queued. Do not start work for it.
        guard !Task.isCancelled else { return }
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
        loadTokens.removeAll()
        cache.removeAllObjects()
    }

    /// Stops decodes for pages that left the reader's window. Without this, a
    /// fast scroll leaves a queue of full-size decodes that keeps the CPU busy
    /// long after those pages became invisible. The token makes the
    /// cancellation a no-op when the page already has a newer owner.
    func cancelLoads(_ requests: [PageSource: UUID], quality: PageRenderQuality = .standard) {
        for (source, token) in requests {
            let key = Self.key(for: source, quality: quality)
            guard loadTokens[key] == token else { continue }
            loadTasks.removeValue(forKey: key)?.cancel()
            loadTokens[key] = nil
            speculativeTasks.removeValue(forKey: key)?.task.cancel()
        }
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

    private func finishLoad(key: String, token: UUID) {
        guard loadTokens[key] == token else { return }
        loadTasks[key] = nil
        loadTokens[key] = nil
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
