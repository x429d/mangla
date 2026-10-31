import CoreGraphics
import Foundation
import ImageIO

enum ImageDecodingError: LocalizedError {
    case cannotOpen(URL)
    case cannotDecode(URL)
    case cannotReadSize(URL)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let url): tf(.decodeCannotOpen, url.lastPathComponent)
        case .cannotDecode(let url): tf(.decodeCannotDecode, url.lastPathComponent)
        case .cannotReadSize(let url): tf(.decodeCannotReadSize, url.lastPathComponent)
        case .invalidData: t(.decodeInvalidImage)
        }
    }
}

/// Errors raised while resolving a page from an archive or a PDF.
enum PageLoadingError: LocalizedError {
    case unavailable(PageSource)

    var errorDescription: String? {
        switch self {
        case .unavailable(let source): tf(.decodeCannotOpen, source.displayName)
        }
    }
}

/// All decoding happens off the main actor. The decoder always asks ImageIO to
/// produce a fully rasterised, GPU-ready bitmap (`ShouldCacheImmediately`)
/// before the image is handed over to AppKit.
enum ImageDecoder {
    nonisolated static func pixelSize(url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        return pixelSize(from: source)
    }

    nonisolated static func decode(url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            throw ImageDecodingError.cannotOpen(url)
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, decodeOptions as CFDictionary) else {
            throw ImageDecodingError.cannotDecode(url)
        }
        return image
    }

    nonisolated static func thumbnail(url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        return thumbnail(from: source, maxPixel: maxPixel)
    }

    // MARK: - In-memory images (archive entries)

    nonisolated static func pixelSize(data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        return pixelSize(from: source)
    }

    nonisolated static func decode(data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw ImageDecodingError.invalidData
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, decodeOptions as CFDictionary) else {
            throw ImageDecodingError.invalidData
        }
        return image
    }

    nonisolated static func thumbnail(data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        return thumbnail(from: source, maxPixel: maxPixel)
    }

    // MARK: - Shared ImageIO work

    private nonisolated static func pixelSize(from source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        guard width > 0, height > 0 else { return nil }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if orientation >= 5 {
            return CGSize(width: height, height: width)
        }
        return CGSize(width: width, height: height)
    }

    private nonisolated static func thumbnail(from source: CGImageSource, maxPixel: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: false,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private nonisolated static var decodeOptions: [CFString: Any] {
        [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: false,
            kCGImageSourceShouldCache: true,
        ]
    }

    private nonisolated static var sourceOptions: CFDictionary {
        [kCGImageSourceShouldCache: false] as CFDictionary
    }
}
