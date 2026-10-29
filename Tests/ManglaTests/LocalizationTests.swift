import XCTest

@testable import Mangla

final class LocalizationTests: XCTestCase {
    private let english = Localization(language: .english)
    private let russian = Localization(language: .russian)

    // MARK: - Language detection

    func testResolvePicksFirstSupportedSystemLanguage() {
        XCTAssertEqual(AppLanguage.resolve(preferred: ["ru-RU"]), .russian)
        XCTAssertEqual(AppLanguage.resolve(preferred: ["en-US"]), .english)
        XCTAssertEqual(AppLanguage.resolve(preferred: ["en-RU", "ru-RU"]), .english)
        XCTAssertEqual(AppLanguage.resolve(preferred: ["ru"]), .russian)
        XCTAssertEqual(AppLanguage.resolve(preferred: ["de-DE", "ru-RU", "en-US"]), .russian)
        XCTAssertEqual(AppLanguage.resolve(preferred: ["fr-FR", "en-GB"]), .english)
        XCTAssertEqual(AppLanguage.resolve(preferred: ["ja-JP"]), .english)
        XCTAssertEqual(AppLanguage.resolve(preferred: []), .english)
    }

    func testUnsupportedSystemLanguageFallsBackToEnglish() {
        XCTAssertEqual(AppLanguage.resolve(preferred: ["de-DE", "fr-FR"]), .english)
    }

    // MARK: - Catalog

    func testEveryKeyHasBothTranslations() {
        for key in LocKey.allCases {
            let englishValue = LocKey.english[key]
            let russianValue = LocKey.russian[key]
            XCTAssertNotNil(englishValue, "Missing English for \(key.rawValue)")
            XCTAssertNotNil(russianValue, "Missing Russian for \(key.rawValue)")
            XCTAssertFalse(englishValue?.isEmpty ?? true, "Empty English for \(key.rawValue)")
            XCTAssertFalse(russianValue?.isEmpty ?? true, "Empty Russian for \(key.rawValue)")
        }
    }

    func testSimpleLookups() {
        XCTAssertEqual(english.text(.ok), "OK")
        XCTAssertEqual(russian.text(.ok), "Хорошо")
        XCTAssertEqual(english.text(.directionRTL), "Right to Left")
        XCTAssertEqual(russian.text(.directionRTL), "Справа налево")
    }

    // MARK: - Plurals

    func testEnglishPlurals() {
        XCTAssertEqual(english.counted(0, .page), "0 pages")
        XCTAssertEqual(english.counted(1, .page), "1 page")
        XCTAssertEqual(english.counted(2, .page), "2 pages")
        XCTAssertEqual(english.counted(1, .chapter), "1 chapter")
        XCTAssertEqual(english.counted(5, .chapter), "5 chapters")
        XCTAssertEqual(english.counted(1, .manga), "1 manga")
        XCTAssertEqual(english.counted(3, .manga), "3 manga")
        XCTAssertEqual(english.counted(1, .collection), "1 collection")
        XCTAssertEqual(english.counted(2, .collection), "2 collections")
    }

    func testRussianPlurals() {
        XCTAssertEqual(russian.counted(0, .page), "0 страниц")
        XCTAssertEqual(russian.counted(1, .page), "1 страница")
        XCTAssertEqual(russian.counted(2, .page), "2 страницы")
        XCTAssertEqual(russian.counted(4, .page), "4 страницы")
        XCTAssertEqual(russian.counted(5, .page), "5 страниц")
        XCTAssertEqual(russian.counted(11, .page), "11 страниц")
        XCTAssertEqual(russian.counted(21, .page), "21 страница")
        XCTAssertEqual(russian.counted(22, .page), "22 страницы")
        XCTAssertEqual(russian.counted(25, .page), "25 страниц")
        XCTAssertEqual(russian.counted(111, .chapter), "111 глав")
        XCTAssertEqual(russian.counted(1, .collection), "1 коллекция")
        XCTAssertEqual(russian.counted(3, .collection), "3 коллекции")
        XCTAssertEqual(russian.counted(5, .collection), "5 коллекций")
    }

    func testCompactCounts() {
        XCTAssertEqual(english.counted(12, .chapter, compact: true), "12 ch.")
        XCTAssertEqual(english.counted(120, .page, compact: true), "120 p.")
        XCTAssertEqual(russian.counted(12, .chapter, compact: true), "12 гл.")
        XCTAssertEqual(russian.counted(120, .page, compact: true), "120 стр.")
    }

    // MARK: - Formatting

    func testFormattedStrings() {
        XCTAssertEqual(
            english.formatted(.toastInvalidPage, arguments: [42]),
            "Enter a page from 1 to 42"
        )
        XCTAssertEqual(
            russian.formatted(.toastInvalidPage, arguments: [42]),
            "Введите страницу от 1 до 42"
        )
        XCTAssertEqual(
            english.formatted(.continueMeta, arguments: ["Chapter 3", 4, 20]),
            "Chapter 3 · p. 4 of 20"
        )
        XCTAssertEqual(
            russian.formatted(.continueMeta, arguments: ["Глава 3", 4, 20]),
            "Глава 3 · стр. 4 из 20"
        )
        XCTAssertEqual(
            english.formatted(.rangeLabel, arguments: [1, 30, 45]),
            "1–30 of 45"
        )
        XCTAssertEqual(
            russian.formatted(.rangeLabel, arguments: [1, 30, 45]),
            "1–30 из 45"
        )
    }
}
