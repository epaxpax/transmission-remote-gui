import Foundation
import Observation

/// Raw values are persisted; keep the existing system/hungarian/english values stable.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, hungarian, english, simplifiedChinese, french
    public var id: String { rawValue }

    public var title: String { pack?.title ?? "System" }
    public var locale: Locale { Locale(identifier: pack?.localeIdentifier ?? "en_US") }

    /// The only registration point when adding another compiled-in language pack.
    public var pack: LanguagePack? {
        switch self {
        case .system: return nil
        case .hungarian:
            return LanguagePack(title: "Magyar", localeIdentifier: "hu_HU", languageCodes: ["hu"])
        case .english: return englishPack
        case .simplifiedChinese: return simplifiedChinesePack
        case .french: return frenchPack
        }
    }

    /// Use the first supported preference. Traditional Chinese does not match zh-Hans.
    public static func resolve(preferredLanguages: [String]) -> AppLanguage {
        for identifier in preferredLanguages {
            if let language = allCases.first(where: { $0.pack?.matches(identifier) == true }) {
                return language
            }
        }
        return .english
    }
}

/// Runtime-switchable localization. UI wrappers read this observable object, so changing
/// the language updates SwiftUI without restarting. Tests use an isolated defaults suite.
@MainActor @Observable
public final class Localization {
    public static let shared = Localization()
    private static let key = "appLanguage"
    private let defaults: UserDefaults
    private let preferredLanguages: () -> [String]

    public var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Self.key) }
    }

    public init(defaults: UserDefaults = .standard,
                preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }) {
        self.defaults = defaults
        self.preferredLanguages = preferredLanguages
        self.language = defaults.string(forKey: Self.key).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    public var effective: AppLanguage {
        language == .system ? AppLanguage.resolve(preferredLanguages: preferredLanguages()) : language
    }

    public var locale: Locale { effective.locale }

    /// Hungarian is the source language. Other packs fall back to English, then the key.
    public func text(_ key: String) -> String {
        let language = effective
        if language == .hungarian { return key }
        return (language.pack ?? englishPack).text(key, fallback: englishPack)
    }

    public func status(_ source: String) -> String {
        let language = effective
        if language == .hungarian { return source }
        func translated(_ key: String) -> String {
            language.pack?.statuses[key] ?? englishPack.statuses[key] ?? key
        }
        // Preserve the progress exactly as supplied by Torrent.statusText.
        let verifyPrefix = "Ellenőrzés "
        if source.hasPrefix(verifyPrefix) {
            return translated("Ellenőrzés") + " " + source.dropFirst(verifyPrefix.count)
        }
        return translated(source)
    }

    /// Only translate a known success token; arbitrary tracker diagnostics are user data.
    public func trackerResult(_ result: String?) -> String {
        guard let result else { return "—" }
        return result == "Success" ? text(result) : result
    }
}
