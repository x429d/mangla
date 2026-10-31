import CoreGraphics
import Foundation
import XCTest

@testable import Mangla

final class ZipArchiveTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManglaZip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeArchive(_ entries: [ZipFixture.Entry], name: String = "book.cbz") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try ZipFixture.build(entries).write(to: url)
        return url
    }

    func testReadsStoredAndDeflatedEntries() throws {
        let page = try ImageFixture.pngData()
        let url = try writeArchive([
            .init(path: "001.jpg", data: page),
            .init(path: "002.jpg", data: page, deflated: true),
        ])

        let archive = try ZipArchive(url: url)
        XCTAssertEqual(try archive.data(for: "001.jpg"), page)
        XCTAssertEqual(try archive.data(for: "002.jpg"), page)
        XCTAssertEqual(archive.entries["002.jpg"]?.method, 8)
    }

    func testEncryptedEntryIsRejected() throws {
        let url = try writeArchive([
            .init(path: "secret.jpg", data: Data("x".utf8), encrypted: true)
        ])
        let archive = try ZipArchive(url: url)

        XCTAssertThrowsError(try archive.data(for: "secret.jpg")) { error in
            guard case ArchiveError.encrypted = error else {
                return XCTFail("Expected encrypted, got \(error)")
            }
        }
    }

    func testMissingEntryThrows() throws {
        let url = try writeArchive([.init(path: "001.jpg", data: Data("x".utf8))])
        let archive = try ZipArchive(url: url)

        XCTAssertThrowsError(try archive.data(for: "nope.jpg")) { error in
            guard case ArchiveError.entryMissing = error else {
                return XCTFail("Expected entryMissing, got \(error)")
            }
        }
    }

    func testNotAnArchiveIsRejected() throws {
        let url = directory.appendingPathComponent("fake.cbz")
        try Data("this is not a zip".utf8).write(to: url)

        XCTAssertThrowsError(try ZipArchive(url: url))
        XCTAssertThrowsError(try ArchiveFormat.detect(url: url)) { error in
            guard case ArchiveError.notAnArchive = error else {
                return XCTFail("Expected notAnArchive, got \(error)")
            }
        }
    }

    func testFilesAreDetectedByContentNotExtension() throws {
        let url = try writeArchive([.init(path: "001.jpg", data: Data("x".utf8))], name: "volume.cbr")
        XCTAssertEqual(try ArchiveFormat.detect(url: url), .zip)
    }

    func testRarMagicIsRecognizedAndBrokenRarDoesNotCrash() throws {
        var data = Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00])
        data.append(contentsOf: [UInt8](repeating: 0, count: 32))
        let url = directory.appendingPathComponent("broken.cbr")
        try data.write(to: url)

        XCTAssertEqual(try ArchiveFormat.detect(url: url), .rar)
        XCTAssertThrowsError(try ArchiveListing.imageEntries(for: url))
    }
}

final class ArchiveListingTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManglaListing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testImagesAreSortedNaturallyAndHiddenEntriesDropped() throws {
        let url = directory.appendingPathComponent("book.cbz")
        try ZipFixture.build([
            .init(path: "10.jpg", data: Data("a".utf8)),
            .init(path: "2.jpg", data: Data("b".utf8)),
            .init(path: "1.jpg", data: Data("c".utf8)),
            .init(path: "cover.png", data: Data("d".utf8)),
            .init(path: "notes.txt", data: Data("e".utf8)),
            .init(path: "__MACOSX/._1.jpg", data: Data("f".utf8)),
            .init(path: ".hidden/2.jpg", data: Data("g".utf8)),
            .init(path: "../escape.jpg", data: Data("h".utf8)),
        ]).write(to: url)

        XCTAssertEqual(
            try ArchiveListing.imageEntries(for: url),
            ["1.jpg", "2.jpg", "10.jpg", "cover.png"]
        )
    }

    func testFullyEncryptedArchiveIsReported() throws {
        let url = directory.appendingPathComponent("book.cbz")
        try ZipFixture.build([
            .init(path: "001.jpg", data: Data("a".utf8), encrypted: true),
            .init(path: "002.jpg", data: Data("b".utf8), encrypted: true),
        ]).write(to: url)

        XCTAssertThrowsError(try ArchiveListing.imageEntries(for: url)) { error in
            guard case ArchiveError.encrypted = error else {
                return XCTFail("Expected encrypted, got \(error)")
            }
        }
    }

    func testEntriesInSubfoldersKeepTheirPath() throws {
        let url = directory.appendingPathComponent("book.cbz")
        try ZipFixture.build([
            .init(path: "Chapter 01/002.jpg", data: Data("a".utf8)),
            .init(path: "Chapter 01/001.jpg", data: Data("b".utf8)),
        ]).write(to: url)

        XCTAssertEqual(
            try ArchiveListing.imageEntries(for: url),
            ["Chapter 01/001.jpg", "Chapter 01/002.jpg"]
        )
    }
}

final class PageFormatTests: XCTestCase {
    func testPathTraversalAndHiddenEntriesAreRejected() {
        XCTAssertTrue(PageFormat.isImageEntry("001.jpg"))
        XCTAssertTrue(PageFormat.isImageEntry("Chapter 01/001.webp"))
        XCTAssertFalse(PageFormat.isImageEntry("../escape.jpg"))
        XCTAssertFalse(PageFormat.isImageEntry("a/../../b.jpg"))
        XCTAssertFalse(PageFormat.isImageEntry("/absolute.jpg"))
        XCTAssertFalse(PageFormat.isImageEntry("__MACOSX/1.jpg"))
        XCTAssertFalse(PageFormat.isImageEntry("._1.jpg"))
        XCTAssertFalse(PageFormat.isImageEntry("notes.txt"))
    }

    func testPagesSortByStemThenPath() {
        let names = ["20.webp", "1.webp", "10.jpg", "2.webp", "3.jpg"]
        XCTAssertEqual(names.sorted(by: PageFormat.pageOrder), ["1.webp", "2.webp", "3.jpg", "10.jpg", "20.webp"])
        XCTAssertFalse(PageFormat.pageOrder("10.jpg", "2.jpg"))
    }

    func testComicExtensionsAreCaseInsensitive() {
        let base = URL(fileURLWithPath: "/tmp")
        XCTAssertTrue(PageFormat.isComicFile(base.appendingPathComponent("A.CBZ")))
        XCTAssertTrue(PageFormat.isComicFile(base.appendingPathComponent("A.cbr")))
        XCTAssertTrue(PageFormat.isComicFile(base.appendingPathComponent("A.pdf")))
        XCTAssertFalse(PageFormat.isComicFile(base.appendingPathComponent("A.zip")))
        XCTAssertFalse(PageFormat.isComicFile(base.appendingPathComponent("A.jpg")))
    }
}

final class ArchiveScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManglaArchiveScan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func writeArchive(
        at relativePath: String,
        entries: [String],
        deflated: Bool = false
    ) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let page = try ImageFixture.pngData()
        let fixture = entries.map {
            ZipFixture.Entry(path: $0, data: page, deflated: deflated)
        }
        try ZipFixture.build(fixture).write(to: url)
        return url
    }

    func testLooseArchiveBecomesItsOwnManga() throws {
        let archive = try writeArchive(
            at: "One Shot.cbz",
            entries: ["001.jpg", "10.jpg", "2.jpg"]
        )
        let chapter = root.appendingPathComponent("Series/Chapter 1", isDirectory: true)
        try FileManager.default.createDirectory(at: chapter, withIntermediateDirectories: true)
        try Data().write(to: chapter.appendingPathComponent("001.png"))

        let snapshot = try LibraryScanner.scan(projectURL: root)
        XCTAssertEqual(snapshot.mangas.map(\.title), ["One Shot", "Series"])

        let manga = try XCTUnwrap(snapshot.mangas.first)
        XCTAssertEqual(manga.containerURL.standardizedFileURL, archive.standardizedFileURL)
        XCTAssertEqual(manga.chapters.count, 1)
        XCTAssertEqual(manga.chapters[0].pages.map(\.name), ["001", "2", "10"])
        guard case .archiveEntry(let coverArchive, let coverEntry) = try XCTUnwrap(manga.coverSource) else {
            return XCTFail("Expected an archive cover")
        }
        XCTAssertEqual(coverArchive.lastPathComponent, "One Shot.cbz")
        XCTAssertEqual(coverEntry, "001.jpg")
        XCTAssertEqual(archive.lastPathComponent, "One Shot.cbz")
    }

    func testArchivesInsideMangaFolderBecomeChapters() throws {
        try writeArchive(at: "Series/Chapter 2.cbz", entries: ["001.jpg", "002.jpg"], deflated: true)
        try writeArchive(at: "Series/Chapter 1.cbz", entries: ["001.jpg", "002.jpg", "003.jpg"])
        let extras = root.appendingPathComponent("Series/Extras", isDirectory: true)
        try FileManager.default.createDirectory(at: extras, withIntermediateDirectories: true)
        try Data().write(to: extras.appendingPathComponent("001.png"))

        let snapshot = try LibraryScanner.scan(projectURL: root)
        let manga = try XCTUnwrap(snapshot.mangas.first)
        XCTAssertEqual(manga.title, "Series")
        XCTAssertEqual(manga.chapters.map(\.title), ["Chapter 1", "Chapter 2", "Extras"])
        XCTAssertEqual(manga.pageCount, 6)
        XCTAssertEqual(manga.chapters[0].containerURL.lastPathComponent, "Chapter 1.cbz")
    }

    func testArchiveChaptersInSubfoldersKeepRelativeTitles() throws {
        try writeArchive(at: "Series/Arc 1/Chapter 1.cbz", entries: ["001.jpg"])

        let snapshot = try LibraryScanner.scan(projectURL: root)
        let manga = try XCTUnwrap(snapshot.mangas.first)
        XCTAssertEqual(manga.chapters.map(\.title), ["Arc 1/Chapter 1"])
    }

    func testCbrThatIsReallyAZipIsReadable() throws {
        try writeArchive(at: "Volume.cbr", entries: ["01.jpg", "02.jpg"])

        let snapshot = try LibraryScanner.scan(projectURL: root)
        XCTAssertEqual(snapshot.mangas.count, 1)
        XCTAssertEqual(snapshot.mangas[0].pageCount, 2)
    }

    func testCorruptArchiveIsSkippedWithoutFailingTheScan() throws {
        try Data("not an archive".utf8).write(to: root.appendingPathComponent("Broken.cbz"))
        let good = root.appendingPathComponent("Good", isDirectory: true)
        try FileManager.default.createDirectory(at: good, withIntermediateDirectories: true)
        try Data().write(to: good.appendingPathComponent("001.png"))

        let snapshot = try LibraryScanner.scan(projectURL: root)
        XCTAssertEqual(snapshot.mangas.map(\.title), ["Good"])
    }

    func testArchiveWithoutImagesIsSkipped() throws {
        let url = root.appendingPathComponent("Empty.cbz")
        try ZipFixture.build([.init(path: "readme.txt", data: Data("x".utf8))]).write(to: url)

        let snapshot = try LibraryScanner.scan(projectURL: root)
        XCTAssertTrue(snapshot.mangas.isEmpty)
    }

    func testPDFIsScannedAsItsOwnManga() throws {
        let pdf = root.appendingPathComponent("Art Book.pdf")
        try PDFFixture.writePDF(
            to: pdf,
            pageSize: CGSize(width: 595, height: 842),
            pageCount: 2
        )

        let snapshot = try LibraryScanner.scan(projectURL: root)
        XCTAssertEqual(snapshot.mangas.map(\.title), ["Art Book"])
        let manga = try XCTUnwrap(snapshot.mangas.first)
        XCTAssertEqual(manga.chapters.count, 1)
        XCTAssertEqual(manga.chapters[0].pages.count, 2)
        guard case .pdfPage(let coverPDF, let pageIndex) = try XCTUnwrap(manga.coverSource) else {
            return XCTFail("Expected a PDF cover")
        }
        XCTAssertEqual(coverPDF.lastPathComponent, "Art Book.pdf")
        XCTAssertEqual(pageIndex, 0)
        XCTAssertEqual(pdf.lastPathComponent, "Art Book.pdf")
    }

    func testPDFInsideMangaFolderBecomesAChapter() throws {
        let folder = root.appendingPathComponent("Series", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try PDFFixture.writePDF(
            to: folder.appendingPathComponent("Volume 1.pdf"),
            pageSize: CGSize(width: 600, height: 900)
        )

        let snapshot = try LibraryScanner.scan(projectURL: root)
        let manga = try XCTUnwrap(snapshot.mangas.first)
        XCTAssertEqual(manga.chapters.map(\.title), ["Volume 1"])
        XCTAssertEqual(manga.pageCount, 1)
    }
}

final class PDFPageReaderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManglaPDF-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testPageCountAndUprightSize() throws {
        let portraitURL = directory.appendingPathComponent("portrait.pdf")
        try PDFFixture.writePDF(
            to: portraitURL,
            pageSize: CGSize(width: 595, height: 842),
            pageCount: 2
        )
        let landscapeURL = directory.appendingPathComponent("landscape.pdf")
        try PDFFixture.writePDF(
            to: landscapeURL,
            pageSize: CGSize(width: 800, height: 600)
        )

        XCTAssertEqual(PDFPageReader.pageCount(url: portraitURL), 2)
        let portrait = try XCTUnwrap(PDFPageReader.pageSize(url: portraitURL, pageIndex: 0))
        XCTAssertEqual(portrait.width, 595, accuracy: 1)
        XCTAssertEqual(portrait.height, 842, accuracy: 1)
        let landscape = try XCTUnwrap(PDFPageReader.pageSize(url: landscapeURL, pageIndex: 0))
        XCTAssertEqual(landscape.width, 800, accuracy: 1)
        XCTAssertEqual(landscape.height, 600, accuracy: 1)
    }

    func testRenderedPageUsesRequestedDetail() throws {
        let url = directory.appendingPathComponent("book.pdf")
        try PDFFixture.writePDF(to: url, pageSize: CGSize(width: 595, height: 842))

        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        let page = try XCTUnwrap(document.page(at: 1))
        let standard = try XCTUnwrap(PDFPageReader.image(page: page, quality: .standard))
        let high = try XCTUnwrap(PDFPageReader.image(page: page, quality: .high))

        XCTAssertEqual(Double(standard.height), 2200, accuracy: 4)
        XCTAssertEqual(Double(high.height), 4400, accuracy: 8)
        XCTAssertLessThan(standard.width, standard.height)
        XCTAssertGreaterThan(high.width, standard.width)
    }

    func testRenderedPageFillsTheWholeBitmap() throws {
        let url = directory.appendingPathComponent("book.pdf")
        try PDFFixture.writePDF(to: url, pageSize: CGSize(width: 595, height: 842))

        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        let page = try XCTUnwrap(document.page(at: 1))
        let image = try XCTUnwrap(PDFPageReader.image(page: page, quality: .standard))

        // The fixture paints its whole page gray. White corners would mean the
        // page was drawn at its natural size in the middle of the bitmap.
        for point in [(4, 4), (image.width - 5, 4), (4, image.height - 5), (image.width - 5, image.height - 5)] {
            let color = try XCTUnwrap(pixelColor(in: image, x: point.0, y: point.1))
            XCTAssertLessThan(color.red, 200, "Unexpected white corner at \(point)")
            XCTAssertLessThan(color.green, 200, "Unexpected white corner at \(point)")
            XCTAssertLessThan(color.blue, 200, "Unexpected white corner at \(point)")
        }
    }

    func testThumbnailFillsRequestedEdge() throws {
        let url = directory.appendingPathComponent("book.pdf")
        try PDFFixture.writePDF(to: url, pageSize: CGSize(width: 595, height: 842))

        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        let page = try XCTUnwrap(document.page(at: 1))
        let image = try XCTUnwrap(PDFPageReader.thumbnail(page: page, maxPixel: 240))
        let color = try XCTUnwrap(pixelColor(in: image, x: 2, y: 2))
        XCTAssertLessThan(color.red, 200)
    }

    private func pixelColor(in image: CGImage, x: Int, y: Int) -> (red: Int, green: Int, blue: Int)? {
        guard let data = image.dataProvider?.data,
            let bytes = CFDataGetBytePtr(data),
            x >= 0, y >= 0, x < image.width, y < image.height
        else { return nil }
        let offset = y * image.bytesPerRow + x * (image.bitsPerPixel / 8)
        // premultipliedFirst + little endian stores BGRA.
        return (Int(bytes[offset + 2]), Int(bytes[offset + 1]), Int(bytes[offset]))
    }

    func testThumbnailFitsRequestedEdge() throws {
        let url = directory.appendingPathComponent("book.pdf")
        try PDFFixture.writePDF(to: url, pageSize: CGSize(width: 595, height: 842))

        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        let page = try XCTUnwrap(document.page(at: 1))
        let thumbnail = try XCTUnwrap(PDFPageReader.thumbnail(page: page, maxPixel: 240))
        XCTAssertEqual(Double(thumbnail.height), 240, accuracy: 2)
    }

    func testPageImageLoaderResolvesPDFSource() async throws {
        let url = directory.appendingPathComponent("book.pdf")
        try PDFFixture.writePDF(to: url, pageSize: CGSize(width: 600, height: 900))
        let source = PageSource.pdfPage(pdfURL: url, pageIndex: 0)

        let size = await PageImageLoader.pixelSize(for: source)
        XCTAssertEqual(size?.width ?? 0, 600, accuracy: 1)
        XCTAssertEqual(size?.height ?? 0, 900, accuracy: 1)

        let image = try await PageImageLoader.image(for: source, quality: .standard)
        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)

        let thumbnail = await PageImageLoader.thumbnail(for: source, maxPixel: 120)
        XCTAssertEqual(Double(thumbnail?.height ?? 0), 120, accuracy: 2)
    }
}

final class ArchivePageLoadingTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManglaArchivePage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testArchiveEntryProbeDecodeAndThumbnail() async throws {
        let page = try ImageFixture.pngData(width: 40, height: 60)
        let url = directory.appendingPathComponent("book.cbz")
        try ZipFixture.build([.init(path: "001.png", data: page, deflated: true)]).write(to: url)
        let source = PageSource.archiveEntry(archiveURL: url, entry: "001.png")

        let size = await PageImageLoader.pixelSize(for: source)
        XCTAssertEqual(size, CGSize(width: 40, height: 60))

        let image = try await PageImageLoader.image(for: source, quality: .standard)
        XCTAssertEqual(image.width, 40)
        XCTAssertEqual(image.height, 60)

        let thumbnail = await PageImageLoader.thumbnail(for: source, maxPixel: 20)
        XCTAssertEqual(thumbnail?.height, 20)
    }

    func testPrefetcherKeepsPDFDetailLevelsSeparate() async throws {
        let url = directory.appendingPathComponent("book.pdf")
        try PDFFixture.writePDF(to: url, pageSize: CGSize(width: 595, height: 842))
        let source = PageSource.pdfPage(pdfURL: url, pageIndex: 0)
        let prefetcher = ImagePrefetcher()

        let standard = try await prefetcher.image(for: source, quality: .standard)
        let high = try await prefetcher.image(for: source, quality: .high)

        XCTAssertGreaterThan(high.height, standard.height)
        let cachedStandard = await prefetcher.cachedImage(for: source, quality: .standard)
        XCTAssertEqual(cachedStandard?.width, standard.width)
        XCTAssertEqual(cachedStandard?.height, standard.height)
        await prefetcher.releaseMemory()
    }

    func testCorruptEntrySurfacesPageLoadingError() async throws {
        let url = directory.appendingPathComponent("book.cbz")
        try ZipFixture.build([.init(path: "001.jpg", data: Data("not an image".utf8))]).write(to: url)
        let source = PageSource.archiveEntry(archiveURL: url, entry: "001.jpg")

        do {
            _ = try await PageImageLoader.image(for: source, quality: .standard)
            XCTFail("Expected a loading error")
        } catch {
            guard case PageLoadingError.unavailable = error else {
                return XCTFail("Expected unavailable, got \(error)")
            }
        }
    }
}

final class RarToolTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManglaRarTool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testListsAndExtractsEntriesWithPatternCharacters() throws {
        guard RarTool.isAvailable else {
            throw XCTSkip("bsdtar is not available on this system")
        }
        let url = directory.appendingPathComponent("book.cbz")
        try ZipFixture.build([
            .init(path: "001 [raw].jpg", data: Data("page one".utf8)),
            .init(path: "002 (v2).jpg", data: Data("page two".utf8)),
        ]).write(to: url)

        let listing = try RarTool.list(url: url)
        XCTAssertTrue(listing.contains("001 [raw].jpg"))
        XCTAssertEqual(try RarTool.data(url: url, entry: "001 [raw].jpg"), Data("page one".utf8))
        XCTAssertEqual(try RarTool.data(url: url, entry: "002 (v2).jpg"), Data("page two".utf8))
    }
}

@MainActor
final class ArchiveReadingSessionTests: XCTestCase {
    // Setup stays inside the test: `XCTestCase.setUpWithError` is nonisolated,
    // while this class needs the main actor for AppModel and ReadingSession.
    func testArchiveChapterBuildsSlotsFromRealPageSizes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManglaArchiveSession-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try ImageFixture.pngData(width: 40, height: 60)
        let second = try ImageFixture.pngData(width: 30, height: 50)
        let url = root.appendingPathComponent("One Shot.cbz")
        try ZipFixture.build([
            .init(path: "001.png", data: first, deflated: true),
            .init(path: "002.png", data: second),
        ]).write(to: url)

        let snapshot = try LibraryScanner.scan(projectURL: root)
        let manga = try XCTUnwrap(snapshot.mangas.first)
        let chapter = try XCTUnwrap(manga.chapters.first)

        let model = AppModel()
        model.persistenceEnabled = false
        model.collections = [
            MangaCollection(
                id: UUID(),
                name: snapshot.name,
                directoryURL: root,
                mangas: snapshot.mangas,
                isAvailable: true,
                lastMangaID: manga.id,
                bookmark: nil
            )
        ]

        let session = ReadingSession(model: model, manga: manga, chapter: chapter)
        for _ in 0..<400 where session.isLoadingChapter {
            try await Task.sleep(for: .milliseconds(5))
        }
        defer { session.close() }

        XCTAssertFalse(session.isLoadingChapter)
        XCTAssertEqual(session.totalPages, 2)
        XCTAssertEqual(
            session.pageSlots.map(\.pixelSize),
            [
                CGSize(width: 40, height: 60),
                CGSize(width: 30, height: 50),
            ])
        guard case .archiveEntry(let archiveURL, let entry) = try XCTUnwrap(session.pageSlots.first?.source) else {
            return XCTFail("Expected an archive page")
        }
        XCTAssertEqual(archiveURL.lastPathComponent, "One Shot.cbz")
        XCTAssertEqual(entry, "001.png")
    }
}
