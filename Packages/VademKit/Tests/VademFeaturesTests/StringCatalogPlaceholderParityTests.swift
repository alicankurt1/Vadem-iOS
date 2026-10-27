import Foundation
import Testing

/// İngilizce değerdeki her biçim belirleyicisi (%@, %lld, %1$@ …) Türkçe değerde aynı sayıda ve türde bulunmalı.
/// Karşılaştırma sıraya değil tür çoklu kümesine bakar: konumlu belirleyiciler yer değiştirebilir.
@Suite("String catalog placeholder parity")
struct StringCatalogPlaceholderParityTests {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let catalogs = [
        "Packages/VademKit/Sources/VademFeatures/Resources/Localizable.xcstrings",
        "Vadem/Localizable.xcstrings",
        "Vadem/AppShortcuts.xcstrings",
        "VademWidget/Localizable.xcstrings",
    ]

    private static func strings(at path: String) throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent(path))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: Any])
        return try strings.mapValues { try #require($0 as? [String: Any]) }
    }

    // MARK: Ayrıştırma

    /// Metindeki belirleyicilerin türleri, sıralı çoklu küme olarak. "%%" kaçışı ve "%#@x@" yer tutucuları sayılmaz.
    static func placeholderTypes(in text: String) -> [String] {
        let cleaned = text.replacingOccurrences(of: "%%", with: "")
            .replacingOccurrences(of: #"%#@[A-Za-z_0-9]+@"#, with: "", options: .regularExpression)
        let regex = try! NSRegularExpression(pattern: #"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?([a-zA-Z@])"#)
        return regex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)).map { match in
            let letter = String(cleaned[Range(match.range(at: 1), in: cleaned)!])
            return letter == "i" ? "d" : letter  // %i ve %d aynı tür
        }.sorted()
    }

    /// Bir yerelleştirmenin "other" biçimine açılmış belirleyici türleri:
    /// düz metin, çoğul varyasyonun other biçimi, ve şablondaki her %#@ad@ için değişimin other biçimi.
    /// Değişimin kendi sayısı (%arg / %lld) bir kez int sayılır.
    static func resolvedTypes(of localization: [String: Any]) -> [String] {
        func value(_ node: Any?) -> String? {
            ((node as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
        }
        func other(_ node: [String: Any]) -> String? {
            if let text = value(node) { return text }
            let plural = (node["variations"] as? [String: Any])?["plural"] as? [String: Any]
            return value(plural?["other"])
        }
        var types: [String] = []
        guard let template = other(localization) else { return [] }
        types += placeholderTypes(in: template)
        let subs = localization["substitutions"] as? [String: Any] ?? [:]
        for (name, sub) in subs where template.contains("%#@\(name)@") {
            guard let sub = sub as? [String: Any] else { continue }
            let plural = (sub["variations"] as? [String: Any])?["plural"] as? [String: Any]
            let form = value(plural?["other"]) ?? ""
            // %arg ve sayıyı gösteren %lld/%d değişimin kendisidir: tek int.
            let own = form.replacingOccurrences(of: "%arg", with: "%lld")
            types += placeholderTypes(in: own)
        }
        return types.sorted()
    }

    // MARK: Testler

    @Test("Placeholder parser reads types, ignores escapes and ordering")
    func parser() {
        #expect(Self.placeholderTypes(in: "%1$@ and %2$lld") == ["@", "d"])
        #expect(Self.placeholderTypes(in: "%2$lld ve %1$@") == ["@", "d"])
        #expect(Self.placeholderTypes(in: "100%% of %@") == ["@"])
        #expect(Self.placeholderTypes(in: "%.2f %d %ld %lld %i") == ["d", "d", "d", "d", "f"])
        #expect(Self.placeholderTypes(in: "%#@payments@ left").isEmpty)
        #expect(Self.placeholderTypes(in: "no placeholders").isEmpty)
    }

    @Test("Turkish keeps every English placeholder with same count and types", arguments: catalogs)
    func placeholdersMatch(path: String) throws {
        var checked = 0
        for (key, entry) in try Self.strings(at: path) {
            if entry["shouldTranslate"] as? Bool == false { continue }
            guard let localizations = entry["localizations"] as? [String: Any],
                  let tr = localizations["tr"] as? [String: Any] else { continue }
            // İngilizce değer yoksa anahtar kaynak metindir.
            let expected: [String]
            if let en = localizations["en"] as? [String: Any] {
                expected = Self.resolvedTypes(of: en)
            } else {
                expected = Self.placeholderTypes(in: key)
            }
            let actual = Self.resolvedTypes(of: tr)
            checked += 1
            #expect(actual == expected, "\(path): '\(key)': Turkish placeholder types \(actual) differ from English \(expected)")
        }
        #expect(checked > 0, "\(path): no entries compared")
    }

    @Test("Every Turkish plural form keeps the placeholders of its own text, none foreign to English", arguments: catalogs)
    func pluralFormsHaveNoForeignPlaceholders(path: String) throws {
        for (key, entry) in try Self.strings(at: path) {
            guard let localizations = entry["localizations"] as? [String: Any],
                  let tr = localizations["tr"] as? [String: Any] else { continue }
            let english: Set<String>
            if let en = localizations["en"] as? [String: Any] { english = Set(Self.resolvedTypes(of: en)) }
            else { english = Set(Self.placeholderTypes(in: key)) }
            var forms: [String] = []
            func collect(_ node: [String: Any]) {
                if let text = (node["stringUnit"] as? [String: Any])?["value"] as? String { forms.append(text) }
                if let plural = (node["variations"] as? [String: Any])?["plural"] as? [String: Any] {
                    for case let form as [String: Any] in plural.values { collect(form) }
                }
                for case let sub as [String: Any] in (node["substitutions"] as? [String: Any])?.values.map({ $0 }) ?? [] { collect(sub) }
            }
            collect(tr)
            for text in forms {
                let foreign = Set(Self.placeholderTypes(in: text.replacingOccurrences(of: "%arg", with: "%lld"))).subtracting(english)
                #expect(foreign.isEmpty, "\(path): '\(key)': Turkish text '\(text)' uses types \(foreign) absent from English")
            }
        }
    }
}
