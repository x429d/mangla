import CoreGraphics
import Foundation

/// Small, bounded concurrency gate used by thumbnail decoding.
actor DecodeGate {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            running = max(0, running - 1)
        } else {
            // The slot is handed over to the next waiter.
            waiters.removeFirst().resume()
        }
    }
}

/// Cheap thumbnails for covers, the sidebar, and the scrubber preview.
actor ThumbnailProvider {
    static let shared = ThumbnailProvider()

    private let cache = NSCache<NSString, CGImage>()
    private var tasks: [String: Task<CGImage?, Never>] = [:]
    private let gate = DecodeGate(limit: 4)

    init() {
        cache.totalCostLimit = 160 * 1024 * 1024
        cache.countLimit = 500
    }

    func thumbnail(for source: PageSource, maxPixel: Int = 512) async -> CGImage? {
        let pixel = max(64, maxPixel)
        let key = "\(source.cacheKey)#\(pixel)"

        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        if let existing = tasks[key] {
            return await existing.value
        }

        let gate = self.gate
        let task = Task.detached(priority: .utility) { () -> CGImage? in
            await gate.acquire()
            let image = await PageImageLoader.thumbnail(for: source, maxPixel: pixel)
            await gate.release()
            return image
        }
        tasks[key] = task

        let image = await task.value
        tasks[key] = nil
        if let image {
            cache.setObject(image, forKey: key as NSString, cost: image.bytesPerRow * image.height)
        }
        return image
    }

}

/// Header-only metadata probe. Reading EXIF dimensions takes a few hundred
/// microseconds per page and lets the reader build exact spreads, including
/// "this page is a wide scan" detection.
actor MetadataProbe {
    static let shared = MetadataProbe()

    private var cache: [PageSource: CGSize] = [:]

    func size(of source: PageSource) async -> CGSize? {
        if let cached = cache[source] { return cached }
        guard let size = await PageImageLoader.pixelSize(for: source), size.isUsable else { return nil }
        cache[source] = size
        return size
    }

    func sizes(for sources: [PageSource]) async -> [PageSource: CGSize] {
        var result: [PageSource: CGSize] = [:]
        result.reserveCapacity(sources.count)
        for source in sources {
            if Task.isCancelled { break }
            if let size = await size(of: source) {
                result[source] = size
            }
        }
        return result
    }
}
