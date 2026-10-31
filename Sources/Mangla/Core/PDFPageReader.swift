import CoreGraphics
import Foundation

/// PDF pages are rasterized with CoreGraphics. Layout only needs the page's
/// aspect ratio, so size probing reads the page box instead of rendering.
enum PDFPageReader {
    static func pageCount(url: URL) -> Int {
        guard let document = CGPDFDocument(url as CFURL) else { return 0 }
        return document.numberOfPages
    }

    static func pageSize(url: URL, pageIndex: Int) -> CGSize? {
        guard let document = CGPDFDocument(url as CFURL),
            let page = document.page(at: pageIndex + 1)
        else { return nil }
        return uprightSize(of: page)
    }

    static func image(page: CGPDFPage, quality: PageRenderQuality) -> CGImage? {
        switch quality {
        case .standard:
            return render(page, targetLongEdge: 2200, range: 2...4)
        case .high:
            return render(page, targetLongEdge: 4400, range: 4...6)
        }
    }

    static func thumbnail(page: CGPDFPage, maxPixel: Int) -> CGImage? {
        render(page, targetLongEdge: CGFloat(max(64, maxPixel)), range: 0.1...4)
    }

    /// Page box with the page's rotation applied, so portrait and landscape
    /// pages keep their visual orientation.
    static func uprightSize(of page: CGPDFPage) -> CGSize {
        var box = page.getBoxRect(.cropBox)
        if box.isEmpty {
            box = page.getBoxRect(.mediaBox)
        }
        guard box.width > 0, box.height > 0 else {
            return CGSize(width: 595, height: 842)
        }
        let angle = ((page.rotationAngle % 360) + 360) % 360
        if angle == 90 || angle == 270 {
            return CGSize(width: box.height, height: box.width)
        }
        return box.size
    }

    private static func render(
        _ page: CGPDFPage,
        targetLongEdge: CGFloat,
        range: ClosedRange<CGFloat>
    ) -> CGImage? {
        let size = uprightSize(of: page)
        let longEdge = max(size.width, size.height)
        guard longEdge > 0 else { return nil }

        let scale = min(max(targetLongEdge / longEdge, range.lowerBound), range.upperBound)
        let pixelWidth = max(1, Int((size.width * scale).rounded()))
        let pixelHeight = max(1, Int((size.height * scale).rounded()))

        guard
            let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else { return nil }

        // PDF pages are transparent by default; the reader expects opaque
        // paper, so the background is painted first.
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.interpolationQuality = .high

        // `getDrawingTransform` fits (and rotates) the page into a rect, but it
        // never enlarges content. Scale the context separately, then let the
        // page transform handle rotation and the crop-box origin.
        let pointsRect = CGRect(origin: .zero, size: size)
        let pageTransform = page.getDrawingTransform(
            .cropBox,
            rect: pointsRect,
            rotate: 0,
            preserveAspectRatio: true
        )
        context.scaleBy(
            x: CGFloat(pixelWidth) / size.width,
            y: CGFloat(pixelHeight) / size.height
        )
        context.concatenate(pageTransform)
        context.drawPDFPage(page)
        return context.makeImage()
    }
}

/// Keeps a handful of parsed PDF documents around; parsing a large document is
/// noticeably slower than rendering a page from it.
actor PDFDocumentStore {
    static let shared = PDFDocumentStore()

    private var documents: [String: CGPDFDocument] = [:]
    private let limit = 6

    func pageCount(url: URL) -> Int {
        guard let document = self.document(for: url) else { return 0 }
        return document.numberOfPages
    }

    func pageSize(url: URL, pageIndex: Int) -> CGSize? {
        guard let document = self.document(for: url),
            let page = document.page(at: pageIndex + 1)
        else { return nil }
        return PDFPageReader.uprightSize(of: page)
    }

    func image(url: URL, pageIndex: Int, quality: PageRenderQuality) -> CGImage? {
        guard let document = self.document(for: url),
            let page = document.page(at: pageIndex + 1)
        else { return nil }
        return PDFPageReader.image(page: page, quality: quality)
    }

    func thumbnail(url: URL, pageIndex: Int, maxPixel: Int) -> CGImage? {
        guard let document = self.document(for: url),
            let page = document.page(at: pageIndex + 1)
        else { return nil }
        return PDFPageReader.thumbnail(page: page, maxPixel: maxPixel)
    }

    private func document(for url: URL) -> CGPDFDocument? {
        let key = ArchiveListing.cacheKey(for: url)
        if let cached = documents[key] { return cached }
        guard let document = CGPDFDocument(url as CFURL) else { return nil }
        if documents.count >= limit {
            documents.removeAll()
        }
        documents[key] = document
        return document
    }
}
