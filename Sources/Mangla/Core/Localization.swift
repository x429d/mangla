import Foundation

// MARK: - Language

/// Languages shipped with the app. English is the development language and
/// the fallback for every unsupported system language.
enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case russian = "ru"

    /// The user's system language restricted to the languages we support.
    ///
    /// macOS keeps the preferred languages in order, so a user with
    /// `["de-DE", "ru-RU", "en-US"]` gets Russian. When none of the preferred
    /// languages is supported the app falls back to English.
    ///
    /// `MANGLA_LANGUAGE=en|ru` overrides the detection for development and
    /// screenshots without touching System Settings.
    static var system: AppLanguage {
        if let override = ProcessInfo.processInfo.environment["MANGLA_LANGUAGE"],
            let language = AppLanguage(rawValue: override.lowercased())
        {
            return language
        }
        return resolve(preferred: Locale.preferredLanguages)
    }

    static func resolve(preferred identifiers: [String]) -> AppLanguage {
        for identifier in identifiers {
            let code =
                Locale(identifier: identifier).language.languageCode?.identifier
                ?? identifier.split(separator: "-").first.map(String.init)
                ?? identifier
            if let language = AppLanguage(rawValue: code.lowercased()) {
                return language
            }
        }
        return .english
    }
}

// MARK: - Plural forms

enum PluralCategory: Sendable {
    case one
    case few
    case many
    case other
}

extension AppLanguage {
    /// Russian uses one/few/many; English only distinguishes singular and
    /// plural. Zero is plural in both languages.
    func pluralCategory(for count: Int) -> PluralCategory {
        let value = abs(count)
        switch self {
        case .english:
            return value == 1 ? .one : .other
        case .russian:
            let mod100 = value % 100
            if mod100 >= 11, mod100 <= 14 { return .many }
            switch value % 10 {
            case 1: return .one
            case 2...4: return .few
            default: return .many
            }
        }
    }
}

/// Nouns that can be counted in the interface. Pages and chapters also have a
/// short form for the compact metadata line on library cards.
enum CountedNoun: Sendable {
    case page
    case chapter
    case manga
    case collection

    func key(for category: PluralCategory) -> LocKey {
        switch (self, category) {
        case (.page, .one): .countPageOne
        case (.page, .few): .countPageFew
        case (.page, .many): .countPageMany
        case (.page, .other): .countPageOther
        case (.chapter, .one): .countChapterOne
        case (.chapter, .few): .countChapterFew
        case (.chapter, .many): .countChapterMany
        case (.chapter, .other): .countChapterOther
        case (.manga, .one): .countMangaOne
        case (.manga, .few): .countMangaFew
        case (.manga, .many): .countMangaMany
        case (.manga, .other): .countMangaOther
        case (.collection, .one): .countCollectionOne
        case (.collection, .few): .countCollectionFew
        case (.collection, .many): .countCollectionMany
        case (.collection, .other): .countCollectionOther
        }
    }

    /// Only pages and chapters have a compact form; other nouns fall back to
    /// their full plural.
    var compactKey: LocKey? {
        switch self {
        case .page: .compactPage
        case .chapter: .compactChapter
        case .manga, .collection: nil
        }
    }
}

// MARK: - Localization

/// Immutable snapshot of one language. `current` is resolved once at launch
/// from the system language; all strings are plain lookups, so the type is
/// safe to use from any isolation domain (menus, AppKit views, scanners).
struct Localization: Sendable {
    let language: AppLanguage

    static let current = Localization(language: .system)

    init(language: AppLanguage) {
        self.language = language
    }

    func text(_ key: LocKey) -> String {
        Self.table(for: language)[key] ?? LocKey.english[key] ?? key.rawValue
    }

    static func table(for language: AppLanguage) -> [LocKey: String] {
        switch language {
        case .english: LocKey.english
        case .russian: LocKey.russian
        }
    }

    func formatted(_ key: LocKey, arguments: [CVarArg]) -> String {
        String(
            format: text(key),
            locale: Locale(identifier: language.rawValue),
            arguments: arguments
        )
    }

    /// "3 pages", or "3 p." with `compact`.
    func counted(_ count: Int, _ noun: CountedNoun, compact: Bool = false) -> String {
        if compact, let key = noun.compactKey {
            return "\(count) \(text(key))"
        }
        let category = language.pluralCategory(for: count)
        return "\(count) \(text(noun.key(for: category)))"
    }
}

/// Localized string for the current system language.
func t(_ key: LocKey) -> String {
    Localization.current.text(key)
}

/// Localized format string with arguments, e.g. `tf(.toastInvalidPage, 42)`.
func tf(_ key: LocKey, _ arguments: CVarArg...) -> String {
    Localization.current.formatted(key, arguments: arguments)
}
