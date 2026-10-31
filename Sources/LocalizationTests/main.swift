import Foundation
import Observation
import TransmissionKit
import TransmissionLocalization

// Same standalone-runner approach as KitTests: no XCTest/Testing or daemon required.
@MainActor
final class Harness {
    var passed = 0
    var failed = 0
    func test(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            passed += 1
            print("  ✅ \(name)")
        } catch {
            failed += 1
            print("  ❌ \(name): \(error)")
        }
    }
    func equal<T: Equatable>(_ actual: T, _ expected: T) throws {
        guard actual == expected else { throw Failure(description: "\(actual) != \(expected)") }
    }
    func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(description: message) }
    }
}
struct Failure: Error, CustomStringConvertible { let description: String }

/// Observation callbacks are @Sendable; the flag is protected by a lock.
final class ObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); defer { lock.unlock() }; value = true }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

let t = Harness()
let suite = "TransmissionLocalizationTests." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let l10n = Localization(defaults: defaults, preferredLanguages: { ["zh-Hans-CN"] })
let englishPack = AppLanguage.english.pack!
let simplifiedChinesePack = AppLanguage.simplifiedChinese.pack!

print("Language selection and persistence")
let preferences: [([String], AppLanguage)] = [
    ([], .english), (["en"], .english), (["en-US"], .english),
    (["en-GB"], .english), (["hu-HU"], .hungarian),
    (["zh"], .simplifiedChinese), (["zh-Hans"], .simplifiedChinese),
    (["zh-Hans-CN"], .simplifiedChinese), (["zh_CN"], .simplifiedChinese),
    (["zh-SG"], .simplifiedChinese), (["ZH-hans"], .simplifiedChinese),
    (["zh-Hant"], .english), (["zh-TW"], .english), (["zh-HK"], .english),
    (["zh-MO"], .english), (["zh-Hant-CN"], .english),
    (["fr-FR", "zh-Hans"], .simplifiedChinese),
    (["fr-FR", "hu"], .hungarian), (["hu", "zh-Hans"], .hungarian),
    (["en", "zh-Hans"], .english), (["de-DE", "fr-FR"], .english),
    (["zh-Hant", "zh-Hans"], .simplifiedChinese),
]
for (codes, expected) in preferences {
    t.test("Resolve \(codes)") { try t.equal(AppLanguage.resolve(preferredLanguages: codes), expected) }
}
t.test("No preference defaults to system") { try t.equal(l10n.language, .system) }
t.test("System resolves Simplified Chinese") { try t.equal(l10n.effective, .simplifiedChinese) }
for language in AppLanguage.allCases {
    t.test("Persist and reload \(language.rawValue)") {
        l10n.language = language
        let reloaded = Localization(defaults: defaults, preferredLanguages: { ["hu"] })
        try t.equal(reloaded.language, language)
        try t.equal(defaults.string(forKey: "appLanguage"), language.rawValue)
    }
}
for value in ["hungarian", "english", "system"] {
    t.test("Existing stored value \(value) is compatible") {
        defaults.set(value, forKey: "appLanguage")
        try t.equal(Localization(defaults: defaults).language.rawValue, value)
    }
}
t.test("Unknown stored value falls back to system") {
    defaults.set("unknown-future-language", forKey: "appLanguage")
    try t.equal(Localization(defaults: defaults).language, .system)
}
t.test("Language picker has unique IDs and a native Chinese name") {
    try t.equal(Set(AppLanguage.allCases.map(\.id)).count, AppLanguage.allCases.count)
    try t.equal(AppLanguage.simplifiedChinese.title, "简体中文")
}

print("\nDictionary coverage and fallback")
t.test("Every static loc() call has a Chinese translation") {
    let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("TransmissionRemoteGUI")
    let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
    let pattern = try NSRegularExpression(pattern: #"\bloc\("((?:\\.|[^"\\])*)"\)"#)
    var keys = Set<String>()
    for case let file as URL in files where file.pathExtension == "swift" {
        let source = try String(contentsOf: file, encoding: .utf8)
        for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            let range = Range(match.range(at: 1), in: source)!
            let literal = "\"" + source[range] + "\""
            keys.insert(try JSONDecoder().decode(String.self, from: Data(literal.utf8)))
        }
    }
    try t.expect(keys.count > 200, "Source scan must find the UI strings")
    let missing = keys.filter { (simplifiedChinesePack.strings[$0] ?? "").isEmpty }.sorted()
    try t.equal(missing, [])
}
for (key, expected) in englishPack.strings.sorted(by: { $0.key < $1.key }) {
    t.test("English unchanged and Chinese covered: \(key)") {
        l10n.language = .english
        try t.equal(l10n.text(key), expected)
        l10n.language = .hungarian
        try t.equal(l10n.text(key), key)
        try t.expect(!(simplifiedChinesePack.strings[key] ?? "").isEmpty, "Missing Chinese translation")
        l10n.language = .simplifiedChinese
        try t.equal(l10n.text(key), simplifiedChinesePack.strings[key]!)
    }
}
t.test("An incomplete future pack falls back to English, then the key") {
    let partial = LanguagePack(title: "Test", localeIdentifier: "fr_FR", languageCodes: ["fr"],
                               strings: ["Hozzáadás": "Ajouter"])
    try t.equal(partial.text("Hozzáadás", fallback: englishPack), "Ajouter")
    try t.equal(partial.text("Leállítás", fallback: englishPack), "Stop")
    try t.equal(partial.text("unknown-key", fallback: englishPack), "unknown-key")
}
// Sidebar section titles pass through groupSection before loc(), so the literal scan
// above cannot discover them. Keep explicit coverage for these upstream additions.
let sidebarAllTitles = [
    ("Összes tracker", "All Trackers", "全部 Tracker"),
    ("Összes mappa", "All Folders", "全部文件夹"),
    ("Összes címke", "All Labels", "全部标签"),
]
for (key, english, chinese) in sidebarAllTitles {
    t.test("Sidebar reset title in all languages: \(key)") {
        l10n.language = .english; try t.equal(l10n.text(key), english)
        l10n.language = .simplifiedChinese; try t.equal(l10n.text(key), chinese)
        l10n.language = .hungarian; try t.equal(l10n.text(key), key)
        l10n.language = .system; try t.equal(l10n.text(key), chinese)
        let englishSystem = Localization(defaults: defaults, preferredLanguages: { ["en-US"] })
        try t.equal(englishSystem.text(key), english)
        try t.equal(LanguagePack(title: "Test", localeIdentifier: "fr_FR", languageCodes: ["fr"])
            .text(key, fallback: englishPack), english)
    }
}
for language in AppLanguage.allCases {
    t.test("Unknown text preserved: \(language.rawValue)") {
        l10n.language = language
        try t.equal(l10n.text("用户名称 / user-data"), "用户名称 / user-data")
    }
}

print("\nTorrent statuses (separate from labels)")
for entry in TorrentRowMenu.layout {
    t.test("Row menu command translated: \(entry.command)") {
        try t.expect(englishPack.strings[entry.titleKey] != nil, "Missing English menu title")
        try t.expect(simplifiedChinesePack.strings[entry.titleKey] != nil, "Missing Chinese menu title")
    }
}
for (key, english, chinese) in [
    ("Sorpozíció", "Queue Position", "队列位置"),
    ("Sor elejére", "Move to Top", "移到顶部"),
    ("Feljebb a sorban", "Move Up", "上移"),
    ("Lejjebb a sorban", "Move Down", "下移"),
    ("Sor végére", "Move to Bottom", "移到底部"),
] {
    t.test("Queue title in all languages: \(key)") {
        l10n.language = .english; try t.equal(l10n.text(key), english)
        l10n.language = .simplifiedChinese; try t.equal(l10n.text(key), chinese)
        l10n.language = .hungarian; try t.equal(l10n.text(key), key)
    }
}
let statuses: [(Torrent.Status, String, String)] = [
    (.stopped, "Stopped", "已停止"), (.queuedToVerify, "Queued to verify", "等待校验"),
    (.verifying, "Verifying", "校验"), (.queuedToDownload, "Queued to download", "等待下载"),
    (.downloading, "Downloading", "下载中"), (.queuedToSeed, "Queued to seed", "等待做种"),
    (.seeding, "Seeding", "做种中"),
]
for (status, english, chinese) in statuses {
    t.test("Status \(status.rawValue) in all languages") {
        l10n.language = .english; try t.equal(l10n.status(status.text), english)
        l10n.language = .simplifiedChinese; try t.equal(l10n.status(status.text), chinese)
        l10n.language = .hungarian; try t.equal(l10n.status(status.text), status.text)
    }
}
for progress in [0.0, 0.45, 1.0] {
    t.test("Verifying preserves progress \(progress)") {
        var torrent = Torrent(id: 1)
        torrent.status = Torrent.Status.verifying.rawValue
        torrent.recheckProgress = progress
        l10n.language = .english
        try t.equal(l10n.status(torrent.statusText), "Verifying " + Format.percent(progress))
        l10n.language = .simplifiedChinese
        try t.equal(l10n.status(torrent.statusText), "校验 " + Format.percent(progress))
        l10n.language = .hungarian
        try t.equal(l10n.status(torrent.statusText), torrent.statusText)
    }
}
t.test("Download tab and downloading status do not collide") {
    l10n.language = .simplifiedChinese
    try t.equal(l10n.text("Letöltés"), "下载")
    try t.equal(l10n.status("Letöltés"), "下载中")
    try t.equal(l10n.status("custom daemon status"), "custom daemon status")
}
t.test("Known tracker success translated, arbitrary diagnostics untouched") {
    l10n.language = .simplifiedChinese
    try t.equal(l10n.trackerResult("Success"), "成功")
    for detail in ["Hozzáadás", "Connection timed out", "", "Tracker returned 403"] {
        try t.equal(l10n.trackerResult(detail), detail)
    }
    try t.equal(l10n.trackerResult(nil), "—")
    l10n.language = .english; try t.equal(l10n.trackerResult("Success"), "Success")
    l10n.language = .hungarian; try t.equal(l10n.trackerResult("Success"), "Success")
}
t.test("Notification title and minutes follow language") {
    l10n.language = .english
    try t.equal(l10n.text("Torrent kész"), "Torrent finished")
    try t.equal(l10n.text("perc"), "min")
    l10n.language = .simplifiedChinese
    try t.equal(l10n.text("Torrent kész"), "种子下载完成")
    try t.equal(l10n.text("perc"), "分钟")
}
for (language, locale) in [(AppLanguage.hungarian, "hu_HU"), (.english, "en_US"), (.simplifiedChinese, "zh_CN")] {
    t.test("Weekday locale for \(language.rawValue)") {
        l10n.language = language
        try t.equal(l10n.locale.identifier, locale)
        let formatter = DateFormatter()
        formatter.locale = l10n.locale
        try t.equal(formatter.veryShortStandaloneWeekdaySymbols.count, 7)
        if language == .simplifiedChinese {
            try t.expect(formatter.veryShortStandaloneWeekdaySymbols.contains("一"), "Monday should be Chinese")
        }
    }
}
t.test("SwiftUI observation invalidates when language changes") {
    let changed = ObservationFlag()
    l10n.language = .english
    withObservationTracking {
        _ = l10n.text("Hozzáadás")
    } onChange: {
        changed.set()
    }
    l10n.language = .simplifiedChinese
    try t.expect(changed.isSet, "Language must trigger view invalidation")
    try t.equal(l10n.text("Hozzáadás"), "添加")
}

print("\n\(t.passed) passed, \(t.failed) failed")
exit(t.failed == 0 ? 0 : 1)
