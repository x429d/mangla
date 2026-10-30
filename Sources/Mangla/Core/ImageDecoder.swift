import CoreGraphics
import Foundation
import ImageIO

enum ImageDecodingError: LocalizedError {
    case cannotOpen(URL)
    case cannotDecode(URL)
    case cannotReadSize(URL)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let url): tf(.decodeCannotOpen, url.lastPathComponent)
        case .cannotDecode(let url): tf(.decodeCannotDecode, url.lastPathComponent)
        case .cannotReadSize(let url): tf(.decodeCannotReadSize, url.lastPathComponent)
        }
    }
}

/// All decoding happens off the main actor. The decoder always asks ImageIO to
/// produce a fully rasterised, GPU-ready bitmap (`ShouldCacheImmediately`)
/// before the image is handed over to AppKit.
enum ImageDecoder {
    nonisolated static func pixelSize(url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
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

    nonisolated static func decode(url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            throw ImageDecodingError.cannotOpen(url)
        }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: false,
            kCGImageSourceShouldCache: true,
        ]
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            throw ImageDecodingError.cannotDecode(url)
        }
        return image
    }

    nonisolated static func thumbnail(url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: false,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private nonisolated static var sourceOptions: CFDictionary {
        [kCGImageSourceShouldCache: false] as CFDictionary
    }
}
