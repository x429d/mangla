import Foundation
import os

/// Thin wrapper around the system `bsdtar` (libarchive), which reads RAR4 and
/// RAR5 archives. macOS ships it, so CBR support does not pull a third-party
/// dependency into the bundle.
enum RarTool {
    static let executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")

    private static let logger = Logger(subsystem: "com.mangla.reader", category: "rar")
    private static let maxListingBytes = 32 * 1024 * 1024
    private static let maxEntryBytes = 512 * 1024 * 1024

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: executableURL.path)
    }

    /// Entry paths as stored in the archive. `bsdtar` normalizes names to the
    /// filesystem form used on this Mac, so the same string can be used to
    /// extract the entry later.
    static func list(url: URL) throws -> [String] {
        let output = try run(
            archiveURL: url,
            arguments: ["-tf", url.path],
            collectOutput: true,
            outputLimit: maxListingBytes
        )
        guard let text = String(data: output, encoding: .utf8) else {
            throw ArchiveError.unreadable(url)
        }
        return
            text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
            .filter { !$0.isEmpty }
    }

    /// Extracts one entry to memory. Used for cover thumbnails, where pulling
    /// the whole archive out of a large CBR would be wasteful.
    static func data(url: URL, entry: String) throws -> Data {
        try run(
            archiveURL: url,
            arguments: ["-xOf", url.path, "--", escapedPattern(entry)],
            collectOutput: true,
            outputLimit: maxEntryBytes
        )
    }

    /// Extracts every entry into `directory` with a single `bsdtar` run. The
    /// caller is responsible for providing an empty destination.
    static func extractAll(url: URL, to directory: URL) throws {
        _ = try run(
            archiveURL: url,
            arguments: ["-xf", url.path, "-C", directory.path],
            collectOutput: false,
            outputLimit: 0
        )
    }

    /// `bsdtar` positional arguments are glob patterns. Page names such as
    /// "001 [raw].jpg" must be escaped or they silently fail to match.
    private static func escapedPattern(_ entry: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(entry.count)
        for character in entry {
            if "\\*?[]".contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    private static func run(
        archiveURL: URL,
        arguments: [String],
        collectOutput: Bool,
        outputLimit: Int
    ) throws -> Data {
        guard isAvailable else { throw ArchiveError.toolUnavailable }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = collectOutput ? pipe : FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            logger.error("Could not launch bsdtar: \(error.localizedDescription, privacy: .public)")
            throw ArchiveError.toolUnavailable
        }

        var output = Data()
        var overflow = false
        if collectOutput {
            let handle = pipe.fileHandleForReading
            while true {
                let chunk: Data?
                do {
                    chunk = try handle.read(upToCount: 1 << 20)
                } catch {
                    logger.error("Could not read bsdtar output: \(error.localizedDescription, privacy: .public)")
                    process.terminate()
                    process.waitUntilExit()
                    throw ArchiveError.unreadable(archiveURL)
                }
                guard let chunk, !chunk.isEmpty else { break }
                if output.count + chunk.count > outputLimit {
                    overflow = true
                    process.terminate()
                    break
                }
                output.append(chunk)
            }
        }

        process.waitUntilExit()
        if overflow { throw ArchiveError.tooLarge(archiveURL) }
        guard process.terminationStatus == 0 else {
            logger.warning(
                "bsdtar exited with \(process.terminationStatus) for \(archiveURL.lastPathComponent, privacy: .public)")
            throw ArchiveError.toolFailed(status: process.terminationStatus)
        }
        return output
    }
}
