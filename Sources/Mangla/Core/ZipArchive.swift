import Compression
import Foundation

enum ArchiveError: LocalizedError {
    case unreadable(URL)
    case notAnArchive(URL)
    case encrypted(URL)
    case unsupportedCompression(URL, method: UInt16)
    case corrupt(URL)
    case entryMissing(URL, String)
    case tooLarge(URL)
    case toolUnavailable
    case toolFailed(status: Int32)
    case pdfUnreadable(URL)

    var errorDescription: String? {
        switch self {
        case .unreadable, .corrupt:
            return t(.archiveUnreadable)
        case .notAnArchive:
            return t(.archiveUnsupported)
        case .encrypted:
            return t(.archiveEncrypted)
        case .unsupportedCompression:
            return t(.archiveUnsupported)
        case .entryMissing(_, let entry):
            return tf(.archiveEntryMissing, entry)
        case .tooLarge:
            return t(.archiveTooLarge)
        case .toolUnavailable:
            return t(.archiveToolUnavailable)
        case .toolFailed:
            return t(.archiveUnreadable)
        case .pdfUnreadable:
            return t(.pdfUnreadable)
        }
    }
}

/// Reader for the ZIP container used by `.cbz` files (and by `.cbr` files that
/// are really ZIPs). Parses the central directory once, then inflates single
/// entries on demand with the system Compression framework.
struct ZipArchive: Sendable {
    struct Entry: Hashable, Sendable {
        let path: String
        let method: UInt16
        let flags: UInt16
        let compressedSize: Int64
        let uncompressedSize: Int64
        let localHeaderOffset: Int64
    }

    let url: URL
    /// File entries keyed by normalized path. Directory entries are dropped.
    let entries: [String: Entry]

    private static let maxEntryBytes: Int64 = 512 * 1024 * 1024
    private static let maxEntryCount = 50_000

    init(url: URL) throws {
        self.url = url
        let fileSize = try Self.fileSize(of: url)
        guard fileSize >= 22 else { throw ArchiveError.notAnArchive(url) }

        let tailLength = Int(min(fileSize, 66_000))
        let tail = try Self.read(url: url, offset: fileSize - Int64(tailLength), length: tailLength)
        let tailBytes = [UInt8](tail)
        guard let eocd = Self.endOfCentralDirectory(in: tailBytes) else {
            throw ArchiveError.notAnArchive(url)
        }

        let eocdFileOffset = fileSize - Int64(tailLength) + Int64(eocd)
        var entryCount = Int(Self.u16(tailBytes, eocd + 10) ?? 0)
        var directorySize = Int64(Self.u32(tailBytes, eocd + 12) ?? 0)
        var directoryOffset = Int64(Self.u32(tailBytes, eocd + 16) ?? 0)

        if entryCount == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            let zip64 = try Self.zip64Directory(
                url: url,
                fileSize: fileSize,
                eocdOffset: eocdFileOffset
            )
            entryCount = zip64.count
            directorySize = zip64.size
            directoryOffset = zip64.offset
        }

        guard directoryOffset >= 0,
            directoryOffset <= fileSize,
            directorySize > 0,
            directorySize <= fileSize - directoryOffset,
            entryCount > 0,
            entryCount <= Self.maxEntryCount
        else {
            throw ArchiveError.corrupt(url)
        }

        let directory = try Self.read(
            url: url,
            offset: directoryOffset,
            length: Int(directorySize)
        )
        self.entries = try Self.parseDirectory(
            [UInt8](directory),
            url: url,
            expected: entryCount,
            fileSize: fileSize
        )
    }

    /// Inflated or stored bytes of one entry.
    func data(for path: String) throws -> Data {
        guard let entry = entries[path] else { throw ArchiveError.entryMissing(url, path) }
        guard entry.flags & 0x0001 == 0 else { throw ArchiveError.encrypted(url) }
        guard entry.compressedSize >= 0,
            entry.uncompressedSize >= 0,
            entry.uncompressedSize <= Self.maxEntryBytes,
            entry.compressedSize <= Self.maxEntryBytes
        else {
            throw ArchiveError.tooLarge(url)
        }

        let header = try Self.read(url: url, offset: entry.localHeaderOffset, length: 30)
        let headerBytes = [UInt8](header)
        guard Self.u32(headerBytes, 0) == 0x0403_4B50 else { throw ArchiveError.corrupt(url) }
        let nameLength = Int(Self.u16(headerBytes, 26) ?? 0)
        let extraLength = Int(Self.u16(headerBytes, 28) ?? 0)
        let payloadOffset = entry.localHeaderOffset + 30 + Int64(nameLength) + Int64(extraLength)
        let payload = try Self.read(
            url: url,
            offset: payloadOffset,
            length: Int(entry.compressedSize)
        )

        switch entry.method {
        case 0:
            guard Int64(payload.count) == entry.uncompressedSize else {
                throw ArchiveError.corrupt(url)
            }
            return payload
        case 8:
            return try Self.inflate(payload, expected: Int(entry.uncompressedSize), url: url)
        default:
            throw ArchiveError.unsupportedCompression(url, method: entry.method)
        }
    }

    // MARK: - Directory parsing

    private static func parseDirectory(
        _ bytes: [UInt8],
        url: URL,
        expected: Int,
        fileSize: Int64
    ) throws -> [String: Entry] {
        var entries: [String: Entry] = [:]
        entries.reserveCapacity(expected)
        var offset = 0

        while offset + 46 <= bytes.count {
            guard u32(bytes, offset) == 0x0201_4B50 else { break }
            let flags = u16(bytes, offset + 8) ?? 0
            let method = u16(bytes, offset + 10) ?? 0
            var compressed = Int64(u32(bytes, offset + 20) ?? 0)
            var uncompressed = Int64(u32(bytes, offset + 24) ?? 0)
            let nameLength = Int(u16(bytes, offset + 28) ?? 0)
            let extraLength = Int(u16(bytes, offset + 30) ?? 0)
            let commentLength = Int(u16(bytes, offset + 32) ?? 0)
            var localOffset = Int64(u32(bytes, offset + 42) ?? 0)

            let nameStart = offset + 46
            let extraStart = nameStart + nameLength
            let recordEnd = extraStart + extraLength + commentLength
            guard nameLength > 0, recordEnd <= bytes.count else { throw ArchiveError.corrupt(url) }

            if compressed == 0xFFFF_FFFF || uncompressed == 0xFFFF_FFFF || localOffset == 0xFFFF_FFFF {
                let extra = Array(bytes[extraStart..<(extraStart + extraLength)])
                let zip64 = zip64Values(
                    extra,
                    needsUncompressed: uncompressed == 0xFFFF_FFFF,
                    needsCompressed: compressed == 0xFFFF_FFFF,
                    needsOffset: localOffset == 0xFFFF_FFFF
                )
                if let value = zip64.uncompressed, value <= UInt64(Int64.max) { uncompressed = Int64(value) }
                if let value = zip64.compressed, value <= UInt64(Int64.max) { compressed = Int64(value) }
                if let value = zip64.offset, value <= UInt64(Int64.max) { localOffset = Int64(value) }
            }

            guard localOffset >= 0,
                localOffset < fileSize,
                compressed >= 0,
                uncompressed >= 0
            else {
                throw ArchiveError.corrupt(url)
            }

            let nameBytes = Array(bytes[nameStart..<extraStart])
            let path = normalize(decodeName(nameBytes, isUTF8: flags & 0x0800 != 0))
            offset = recordEnd

            guard !path.isEmpty, !path.hasSuffix("/") else { continue }
            guard entries[path] == nil else { continue }
            entries[path] = Entry(
                path: path,
                method: method,
                flags: flags,
                compressedSize: compressed,
                uncompressedSize: uncompressed,
                localHeaderOffset: localOffset
            )
        }

        guard !entries.isEmpty || expected == 0 else { throw ArchiveError.corrupt(url) }
        return entries
    }

    private struct Zip64Values {
        var uncompressed: UInt64?
        var compressed: UInt64?
        var offset: UInt64?
    }

    private static func zip64Values(
        _ extra: [UInt8],
        needsUncompressed: Bool,
        needsCompressed: Bool,
        needsOffset: Bool
    ) -> Zip64Values {
        var values = Zip64Values()
        var index = 0
        while index + 4 <= extra.count {
            let identifier = u16(extra, index) ?? 0
            let size = Int(u16(extra, index + 2) ?? 0)
            index += 4
            guard index + size <= extra.count else { break }
            if identifier == 0x0001 {
                var cursor = index
                if needsUncompressed, let value = u64(extra, cursor) {
                    values.uncompressed = value
                    cursor += 8
                }
                if needsCompressed, let value = u64(extra, cursor) {
                    values.compressed = value
                    cursor += 8
                }
                if needsOffset, let value = u64(extra, cursor) {
                    values.offset = value
                }
            }
            index += size
        }
        return values
    }

    private static func endOfCentralDirectory(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        var index = bytes.count - 22
        while index >= 0 {
            if u32(bytes, index) == 0x0605_4B50 {
                let commentLength = Int(u16(bytes, index + 20) ?? 0)
                if index + 22 + commentLength <= bytes.count {
                    return index
                }
            }
            if index == 0 { break }
            index -= 1
        }
        return nil
    }

    private static func zip64Directory(
        url: URL,
        fileSize: Int64,
        eocdOffset: Int64
    ) throws -> (count: Int, size: Int64, offset: Int64) {
        let locatorOffset = eocdOffset - 20
        guard locatorOffset >= 0 else { throw ArchiveError.corrupt(url) }
        let locator = try read(url: url, offset: locatorOffset, length: 20)
        let locatorBytes = [UInt8](locator)
        guard u32(locatorBytes, 0) == 0x0706_4B50,
            let recordOffset = u64(locatorBytes, 8),
            recordOffset <= UInt64(Int64.max),
            Int64(recordOffset) < fileSize
        else {
            throw ArchiveError.corrupt(url)
        }

        let record = try read(url: url, offset: Int64(recordOffset), length: 56)
        let recordBytes = [UInt8](record)
        guard u32(recordBytes, 0) == 0x0606_4B50,
            let count = u64(recordBytes, 32),
            let sizeBytes = u64(recordBytes, 40),
            let offsetBytes = u64(recordBytes, 48),
            count <= UInt64(maxEntryCount),
            sizeBytes <= UInt64(Int64.max),
            offsetBytes <= UInt64(Int64.max)
        else {
            throw ArchiveError.corrupt(url)
        }
        return (Int(count), Int64(sizeBytes), Int64(offsetBytes))
    }

    // MARK: - IO

    private static func fileSize(of url: URL) throws -> Int64 {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize else { throw ArchiveError.unreadable(url) }
            return Int64(size)
        } catch {
            throw ArchiveError.unreadable(url)
        }
    }

    private static func read(url: URL, offset: Int64, length: Int) throws -> Data {
        guard offset >= 0, length >= 0 else { throw ArchiveError.corrupt(url) }
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ArchiveError.unreadable(url)
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: UInt64(offset))
            var data = Data()
            data.reserveCapacity(length)
            while data.count < length {
                let chunk = try handle.read(upToCount: length - data.count)
                guard let chunk, !chunk.isEmpty else { break }
                data.append(chunk)
            }
            guard data.count == length else { throw ArchiveError.corrupt(url) }
            return data
        } catch let error as ArchiveError {
            throw error
        } catch {
            throw ArchiveError.unreadable(url)
        }
    }

    // MARK: - Decompression

    private static func inflate(_ data: Data, expected: Int, url: URL) throws -> Data {
        guard expected > 0 else {
            guard data.isEmpty else { throw ArchiveError.corrupt(url) }
            return Data()
        }
        guard !data.isEmpty else { throw ArchiveError.corrupt(url) }

        var output = [UInt8](repeating: 0, count: expected)
        let decoded = output.withUnsafeMutableBufferPointer { destination in
            data.withUnsafeBytes { source in
                guard let destinationBase = destination.baseAddress,
                    let sourceBase = source.bindMemory(to: UInt8.self).baseAddress
                else {
                    return 0
                }
                return compression_decode_buffer(
                    destinationBase,
                    destination.count,
                    sourceBase,
                    source.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decoded == expected else { throw ArchiveError.corrupt(url) }
        return Data(output)
    }

    // MARK: - Name decoding / parsing helpers

    private static func decodeName(_ bytes: [UInt8], isUTF8: Bool) -> String {
        if let name = String(bytes: bytes, encoding: .utf8) { return name }
        if isUTF8 { return String(decoding: bytes, as: UTF8.self) }
        return String(bytes: bytes, encoding: .isoLatin1) ?? String(decoding: bytes, as: UTF8.self)
    }

    private static func normalize(_ path: String) -> String {
        PageFormat.normalizedEntryPath(path)
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }

    private static func u64(_ bytes: [UInt8], _ offset: Int) -> UInt64? {
        guard offset >= 0, offset + 8 <= bytes.count else { return nil }
        var value: UInt64 = 0
        for index in (0..<8).reversed() {
            value = (value << 8) | UInt64(bytes[offset + index])
        }
        return value
    }
}
