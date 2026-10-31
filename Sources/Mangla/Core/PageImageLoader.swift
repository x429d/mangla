import CoreGraphics
import Foundation
import os

/// Resolves any `PageSource` to pixels or dimensions, regardless of whether the
/// page is a plain image file, an archive entry, or a PDF page.
enum PageImageLoader {
    private static let logger = Logger(subsystem: "com.mangla.reader", category: "page")

    /// Extracts the archives a chapter needs before its pages are probed. A
    /// single batch extraction is much cheaper than one process per page.
    static func prepare(_ sources: [PageSource]) async {
        await ArchiveStore.shared.prepare(sources)
    }

    static func pixelSize(for source: PageSource) async -> CGSize? {
        switch source {
        case .imageFile(let url):
            return ImageDecoder.pixelSize(url: url)
        case .archiveEntry:
            do {
                let data = try await ArchiveStore.shared.imageData(for: source)
                return ImageDecoder.pixelSize(data: data)
            } catch {
                logger.debug(
                    "Could not probe \(source.cacheKey, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        case .pdfPage(let pdf, let index):
            return await PDFDocumentStore.shared.pageSize(url: pdf, pageIndex: index)
        }
    }

    static func image(for source: PageSource, quality: PageRenderQuality) async throws -> CGImage {
        switch source {
        case .imageFile(let url):
            return try ImageDecoder.decode(url: url)
        case .archiveEntry:
            do {
                let data = try await ArchiveStore.shared.imageData(for: source)
                return try ImageDecoder.decode(data: data)
            } catch {
                logger.error(
                    "Could not decode \(source.cacheKey, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                throw PageLoadingError.unavailable(source)
            }
        case .pdfPage(let pdf, let index):
            guard
                let image = await PDFDocumentStore.shared.image(
                    url: pdf,
                    pageIndex: index,
                    quality: quality
                )
            else {
                throw ArchiveError.pdfUnreadable(pdf)
            }
            return image
        }
    }

    static func thumbnail(for source: PageSource, maxPixel: Int) async -> CGImage? {
        switch source {
        case .imageFile(let url):
            return ImageDecoder.thumbnail(url: url, maxPixel: maxPixel)
        case .archiveEntry:
            do {
                let data = try await ArchiveStore.shared.imageData(for: source)
                return ImageDecoder.thumbnail(data: data, maxPixel: maxPixel)
            } catch {
                logger.debug(
                    "Could not thumbnail \(source.cacheKey, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        case .pdfPage(let pdf, let index):
            return await PDFDocumentStore.shared.thumbnail(
                url: pdf,
                pageIndex: index,
                maxPixel: maxPixel
            )
        }
    }
}
