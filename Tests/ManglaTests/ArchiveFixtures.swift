import Compression
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

enum FixtureError: Error {
    case imageCreationFailed
    case pdfCreationFailed
    case compressionFailed
}

/// Builds ZIP containers in memory so archive tests do not depend on external
/// tools. Only the fields the reader parses are meaningful; the CRC is left at
/// zero because the app never verifies it.
enum ZipFixture {
    struct Entry {
        let path: String
        let data: Data
        var deflated: Bool = false
        var encrypted: Bool = false
    }

    static func build(_ entries: [Entry]) throws -> Data {
        var output = Data()
        var central = Data()

        for entry in entries {
            let payload: Data
            let method: UInt16
            if entry.deflated {
                payload = try deflate(entry.data)
                method = 8
            } else {
                payload = entry.data
                method = 0
            }
            let name = Data(entry.path.utf8)
            let localOffset = UInt32(output.count)
            let checksum = crc32(entry.data)
            var flags: UInt16 = 0x0800
            if entry.encrypted { flags |= 0x0001 }

            output.appendLE(0x0403_4B50, bytes: 4)
            output.appendLE(20, bytes: 2)
            output.appendLE(flags, bytes: 2)
            output.appendLE(method, bytes: 2)
            output.appendLE(UInt16(0), bytes: 2)
            output.appendLE(UInt16(0), bytes: 2)
            output.appendLE(checksum, bytes: 4)
            output.appendLE(UInt32(payload.count), bytes: 4)
            output.appendLE(UInt32(entry.data.count), bytes: 4)
            output.appendLE(UInt16(name.count), bytes: 2)
            output.appendLE(UInt16(0), bytes: 2)
            output.append(name)
            output.append(payload)

            central.appendLE(0x0201_4B50, bytes: 4)
            central.appendLE(20, bytes: 2)
            central.appendLE(20, bytes: 2)
            central.appendLE(flags, bytes: 2)
            central.appendLE(method, bytes: 2)
            central.appendLE(UInt16(0), bytes: 2)
            central.appendLE(UInt16(0), bytes: 2)
            central.appendLE(checksum, bytes: 4)
            central.appendLE(UInt32(payload.count), bytes: 4)
            central.appendLE(UInt32(entry.data.count), bytes: 4)
            central.appendLE(UInt16(name.count), bytes: 2)
            central.appendLE(UInt16(0), bytes: 2)
            central.appendLE(UInt16(0), bytes: 2)
            central.appendLE(UInt16(0), bytes: 2)
            central.appendLE(UInt16(0), bytes: 2)
            central.appendLE(UInt32(0), bytes: 4)
            central.appendLE(localOffset, bytes: 4)
            central.append(name)
        }

        let centralOffset = UInt32(output.count)
        output.append(central)
        output.appendLE(0x0605_4B50, bytes: 4)
        output.appendLE(UInt16(0), bytes: 2)
        output.appendLE(UInt16(0), bytes: 2)
        output.appendLE(UInt16(entries.count), bytes: 2)
        output.appendLE(UInt16(entries.count), bytes: 2)
        output.appendLE(UInt32(central.count), bytes: 4)
        output.appendLE(centralOffset, bytes: 4)
        output.appendLE(UInt16(0), bytes: 2)
        return output
    }

    /// Standard CRC-32 (ZIP polynomial). The app ignores the checksum, but
    /// `bsdtar` validates it when these fixtures are used to exercise RAR
    /// plumbing, so the archives must be well formed.
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func deflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        let capacity = max(64, data.count * 2 + 64)
        var buffer = [UInt8](repeating: 0, count: capacity)
        let written = buffer.withUnsafeMutableBufferPointer { destination in
            data.withUnsafeBytes { source in
                guard let destinationBase = destination.baseAddress,
                    let sourceBase = source.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_encode_buffer(
                    destinationBase,
                    destination.count,
                    sourceBase,
                    source.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { throw FixtureError.compressionFailed }
        return Data(buffer.prefix(written))
    }
}

enum ImageFixture {
    static func pngData(width: Int = 8, height: Int = 12) throws -> Data {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(red: 0.4, green: 0.6, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())

        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                data,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.imageCreationFailed }
        return data as Data
    }
}

enum PDFFixture {
    static func writePDF(to url: URL, pageSize: CGSize, pageCount: Int = 1) throws {
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw FixtureError.pdfCreationFailed
        }
        for _ in 0..<max(1, pageCount) {
            context.beginPDFPage(nil)
            context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            context.fill(mediaBox)
            context.endPDFPage()
        }
        context.closePDF()
    }
}

extension Data {
    fileprivate mutating func appendLE<T: FixedWidthInteger>(_ value: T, bytes: Int) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { raw in
            append(contentsOf: raw.prefix(bytes))
        }
    }
}
