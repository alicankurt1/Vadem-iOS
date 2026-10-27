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

    /// Bir yerelleştirmenin her biçiminin belirleyici türleri (sıralı çoklu küme), biçim yoluna göre:
    /// "plain" (düz metin), "plural.<biçim>" (çoğul varyasyon), "sub.<ad>.plural.<biçim>" (değişim çoğulu).
    /// Değişim metinlerinde %arg, değişimin kendi sayısıdır: %lld sayılır.
    static func formTypes(of localization: [String: Any]) -> [String: [String]] {
        func text(_ node: Any?) -> String? {
            ((node as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
        }
        func pluralForms(_ node: [String: Any]) -> [String: Any] {
            (node["variations"] as? [String: Any])?["plural"] as? [String: Any] ?? [:]
        }
        var result: [String: [String]] = [:]
        if let plain = text(localization) { result["plain"] = placeholderTypes(in: plain) }
        for (form, node) in pluralForms(localization) {
            result["plural.\(form)"] = placeholderTypes(in: text(node) ?? "")
        }
        let subs = localization["substitutions"] as? [String: Any] ?? [:]
        for (name, sub) in subs {
            guard let sub = sub as? [String: Any] else { continue }
            for (form, node) in pluralForms(sub) {
                let own = (text(node) ?? "").replacingOccurrences(of: "%arg", with: "%lld")
                result["sub.\(name).plural.\(form)"] = placeholderTypes(in: own)
            }
        }
        return result
    }

    /// Türkçe biçimleri İngilizce karşılıklarıyla karşılaştırır; uyuşmazlıkları metin olarak döner.
    /// Aynı adlı biçim varsa onunla, yoksa aynı gruptaki İngilizce "other" (ya da düz metin) ile eşleşir.
    /// İngilizce "other"/düz metin biçimi Türkçede hiç yoksa o da uyuşmazlıktır.
    static func mismatches(en: [String: [String]], tr: [String: [String]]) -> [String] {
        func group(_ key: String) -> String {
            key.range(of: "plural.").map { String(key[..<$0.lowerBound]) } ?? ""
        }
        var problems: [String] = []
        for (key, actual) in tr {
            let fallback = en[group(key) + "plural.other"] ?? en["plain"]
            guard let expected = en[key] ?? fallback else {
                problems.append("\(key): no English counterpart")
                continue
            }
            if actual != expected { problems.append("\(key): Turkish \(actual) vs English \(expected)") }
        }
        for key in en.keys where (key.hasSuffix("plural.other") || key == "plain") && tr[key] == nil {
            problems.append("\(key): missing in Turkish")
        }
        return problems
    }

    /// Anahtar kaynak metinse (İngilizce değer yok) İngilizce biçimi anahtarın kendisidir.
    static func englishForms(_ localizations: [String: Any], key: String) -> [String: [String]] {
        if let en = localizations["en"] as? [String: Any] { return formTypes(of: en) }
        return ["plain": placeholderTypes(in: key)]
    }

    /// Aynı biçimde iki metin (düz) için uyuşmazlık var mı?
    static func isMismatch(en: String, tr: String) -> Bool {
        !mismatches(en: ["plain": placeholderTypes(in: en)], tr: ["plain": placeholderTypes(in: tr)]).isEmpty
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
        #expect(Self.placeholderTypes(in: "%1$@ is 100%% of %2$lld") == ["@", "d"])
        #expect(Self.placeholderTypes(in: "%lu items") == ["u"])
    }

    @Test("Mismatched English/Turkish pairs are detected", arguments: [
        ("%@ paid %lld", "%@ ödendi"),
        ("%@", "%lld"),
        ("Total", "Toplam %@"),
        ("%@ and %@", "%@"),
    ])
    func mismatchDetected(en: String, tr: String) {
        #expect(Self.isMismatch(en: en, tr: tr))
    }

    @Test("Matching pairs are not flagged, even reordered or with escapes", arguments: [
        ("%1$@ paid %2$lld", "%2$lld ile %1$@ ödendi"),
        ("100%% of %@", "%@ değerinin %%100"),
        ("Total", "Toplam"),
    ])
    func matchAccepted(en: String, tr: String) {
        #expect(!Self.isMismatch(en: en, tr: tr))
    }

    @Test("Plural forms are compared per form, with other as fallback")
    func perFormComparison() {
        // İki dilde de "one" sayıyı düşürürse geçer.
        #expect(Self.mismatches(
            en: ["plural.one": [], "plural.other": ["d"]],
            tr: ["plural.one": [], "plural.other": ["d"]]).isEmpty)
        // Türkçe "one" sayıyı düşürür, İngilizce düşürmez: hata.
        #expect(!Self.mismatches(
            en: ["plural.one": ["d"], "plural.other": ["d"]],
            tr: ["plural.one": [], "plural.other": ["d"]]).isEmpty)
        // İngilizcede olmayan Türkçe biçim "other" ile karşılaştırılır.
        #expect(Self.mismatches(en: ["plural.other": ["d"]], tr: ["plural.few": ["d"], "plural.other": ["d"]]).isEmpty)
        #expect(!Self.mismatches(en: ["plural.other": ["d"]], tr: ["plural.few": ["@"], "plural.other": ["d"]]).isEmpty)
        // Eksik "other" yakalanır.
        #expect(!Self.mismatches(en: ["plural.other": ["d"]], tr: ["plural.one": ["d"]]).isEmpty)
    }

    @Test("Every Turkish form keeps the placeholders of its English counterpart", arguments: catalogs)
    func placeholdersMatch(path: String) throws {
        var checked = 0
        for (key, entry) in try Self.strings(at: path) {
            if entry["shouldTranslate"] as? Bool == false { continue }
            guard let localizations = entry["localizations"] as? [String: Any],
                  let tr = localizations["tr"] as? [String: Any] else { continue }
            let problems = Self.mismatches(en: Self.englishForms(localizations, key: key), tr: Self.formTypes(of: tr))
            checked += 1
            #expect(problems.isEmpty, "\(path): '\(key)': \(problems)")
        }
        #expect(checked > 0, "\(path): no entries compared")
    }
}
