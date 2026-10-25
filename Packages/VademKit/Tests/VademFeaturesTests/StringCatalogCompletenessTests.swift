import Foundation
import Testing

/// Koddaki her kullanıcıya görünen metin bir String Catalog anahtarına bağlı olmalı.
/// Kaynak dosyalar metin olarak taranır; yeni bir görünüm metni kataloğu atlarsa test düşer.
@Suite("String catalog completeness")
struct StringCatalogCompletenessTests {
    // MARK: Konumlar

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()  // VademFeaturesTests -> Tests
        .deletingLastPathComponent().deletingLastPathComponent()  // VademKit -> Packages
        .deletingLastPathComponent()                              // -> repo kökü

    private static func url(_ path: String) -> URL { repoRoot.appendingPathComponent(path) }

    private struct Module: Sendable {
        let name: String
        let sourceDirs: [String]
        let catalogs: [String]
        /// Paket modülünde literal görünüm metinleri `bundle: .module` ister; uygulama/widget'ta ana bundle yeter.
        let isPackage: Bool
    }

    private static let modules: [Module] = [
        Module(name: "VademFeatures", sourceDirs: ["Packages/VademKit/Sources/VademFeatures"],
               catalogs: ["Packages/VademKit/Sources/VademFeatures/Resources/Localizable.xcstrings"], isPackage: true),
        Module(name: "Vadem app", sourceDirs: ["Vadem"],
               catalogs: ["Vadem/Localizable.xcstrings", "Vadem/AppShortcuts.xcstrings"], isPackage: false),
        Module(name: "VademWidget", sourceDirs: ["VademWidget"],
               catalogs: ["VademWidget/Localizable.xcstrings"], isPackage: false),
    ]

    // MARK: Katalog okuma

    private static func catalog(at path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: url(path))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(json["strings"] as? [String: Any])
    }

    // Anahtar karşılaştırması için biçim belirleyicileri ve enterpolasyonlar tek işarete indirilir.
    private static func normalize(_ key: String, fromCode: Bool = false) -> String {
        var text = key
        text = text.replacingOccurrences(of: #"\\\((?:[^()]|\([^()]*\))*\)"#, with: "§", options: .regularExpression)
        // Kodda yazılan "%" anahtarda "%%" olur (LocalizedStringKey kaçışı).
        if fromCode { text = text.replacingOccurrences(of: "%", with: "%%") }
        text = text.replacingOccurrences(of: #"%(?:\d+\$)?(?:l+d|d|@|f|lf|ld|lld)"#, with: "§", options: .regularExpression)
        text = text.replacingOccurrences(of: "${applicationName}", with: "§")
        return text
    }

    private static func sourceFiles(in dirs: [String]) -> [URL] {
        var files: [URL] = []
        for dir in dirs {
            guard let enumerator = FileManager.default.enumerator(at: url(dir), includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in enumerator where file.pathExtension == "swift" { files.append(file) }
        }
        return files.sorted { $0.path < $1.path }
    }

    // Önizlemeler (#Preview) kullanıcıya görünmez; dosyanın o noktadan sonrası taranmaz.
    private static func productionText(of file: URL) throws -> String {
        let text = try String(contentsOf: file, encoding: .utf8)
        if let range = text.range(of: "#Preview") { return String(text[..<range.lowerBound]) }
        return text
    }

    // Yorum satırları (// ve ///) taramadan çıkarılır.
    private static func stripComments(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            guard let range = line.range(of: "//") else { return String(line) }
            // "//" bir string içinde olabilir (ör. URL); yalnızca tırnak sayısı çiftse yorumdur.
            let before = line[..<range.lowerBound]
            return before.filter { $0 == "\"" }.count % 2 == 0 ? String(before) : String(line)
        }.joined(separator: "\n")
    }

    private static let literal = #""((?:[^"\\]|\\.|\\\((?:[^()]|\([^()]*\))*\))*)""#

    /// Koddan çıkan (anahtar, dosya) çiftleri.
    private static func usedKeys(in module: Module) throws -> [(key: String, file: String)] {
        var patterns = [
            #"localized:\s*"# + literal,                      // String(localized:), AttributedString(localized:)
            #"\(\s*"# + literal + #"\s*,\s*bundle:\s*\.module"#,          // Text("…", bundle: .module) ve benzerleri
        ]
        if !module.isPackage {
            patterns += [
                #"\b(?:Text|Label|Button|Section|Toggle|Link)\(\s*"# + literal,
                #"LocalizedStringResource\s*=\s*"# + literal,
                #"IntentDescription\(\s*"# + literal,
                #"(?:configurationDisplayName|description)\(\s*"# + literal,
                #"shortTitle:\s*"# + literal,
            ]
        }
        var result: [(String, String)] = []
        for file in sourceFiles(in: module.sourceDirs) {
            let text = stripComments(try productionText(of: file))
            let range = NSRange(text.startIndex..., in: text)
            for pattern in patterns {
                let regex = try NSRegularExpression(pattern: pattern)
                for match in regex.matches(in: text, range: range) {
                    guard let keyRange = Range(match.range(at: 1), in: text) else { continue }
                    result.append((String(text[keyRange]), file.lastPathComponent))
                }
            }
        }
        return result
    }

    // MARK: Testler

    @Test("Every localized key used in code exists in the module's catalog", arguments: modules.map(\.name))
    func keysExist(moduleName: String) throws {
        let module = try #require(Self.modules.first { $0.name == moduleName })
        var catalogKeys = Set<String>()
        for path in module.catalogs { catalogKeys.formUnion(try Self.catalog(at: path).keys.map { Self.normalize($0) }) }
        let used = try Self.usedKeys(in: module)
        // Tarayıcı gerçekten bir şey bulmalı; yoksa test boşuna yeşil olurdu.
        #expect(used.count >= 3, "Scanner found no localized keys in \(moduleName)")
        for (key, file) in used where !key.isEmpty {
            #expect(catalogKeys.contains(Self.normalize(key, fromCode: true)), "\(file): key missing from catalog: \(key)")
        }
    }

    // Paket içinde Text("…") ana bundle'da arar; bundle: .module olmadan çeviri hiç bulunmaz.
    private static let viewConstructors = [
        "Text", "Button", "Label", "Section", "TextField", "SecureField", "Toggle", "Picker", "Link",
        "LabeledContent", "ContentUnavailableView", "NavigationLink", "DatePicker", "Stepper", "Menu", "TextEditor",
    ]
    private static let viewModifiers = [
        "navigationTitle", "accessibilityLabel", "accessibilityHint", "accessibilityValue", "help", "badge",
        "confirmationDialog", "alert",
    ]

    // Açılış parantezinden eşleşen kapanışa kadar çağrının metni (string içindeki parantezler sayılmaz).
    private static func callText(in text: String, openParen: String.Index) -> Substring {
        var depth = 0
        var inString = false
        var index = openParen
        while index < text.endIndex {
            let char = text[index]
            if inString {
                if char == "\\" { index = text.index(after: index) } else if char == "\"" { inString = false }
            } else if char == "\"" {
                inString = true
            } else if char == "(" {
                depth += 1
            } else if char == ")" {
                depth -= 1
                if depth == 0 { return text[openParen...index] }
            }
            index = text.index(after: index)
        }
        return text[openParen...]
    }

    @Test("No view in VademFeatures takes a string literal without bundle: .module")
    func noHardCodedViewStrings() throws {
        let module = Self.modules[0]
        let names = (Self.viewConstructors + Self.viewModifiers).joined(separator: "|")
        let regex = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])(?:"# + names + #")\(\s*""#)
        var offenders: [String] = []
        for file in Self.sourceFiles(in: module.sourceDirs) {
            let text = Self.stripComments(try Self.productionText(of: file))
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let whole = Range(match.range, in: text),
                      let open = text[whole].firstIndex(of: "(") else { continue }
                let call = Self.callText(in: text, openParen: open)
                if !call.contains("bundle:") { offenders.append("\(file.lastPathComponent): \(call.prefix(80))") }
            }
        }
        #expect(offenders.isEmpty, "String literals that bypass the catalog: \(offenders)")
    }

    @Test("Verbatim texts in VademFeatures hold no words (numbers and symbols only)")
    func noVerbatimWords() throws {
        for file in Self.sourceFiles(in: Self.modules[0].sourceDirs) {
            let text = Self.stripComments(try Self.productionText(of: file))
            // Text(verbatim:) yerelleştirmeyi atlar; yalnızca enterpolasyon/sayı/simge olabilir.
            let regex = try NSRegularExpression(pattern: #"(?:Text|Label)\(verbatim:\s*"# + Self.literal)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let stripped = Self.normalize(String(text[range]))
                #expect(stripped.rangeOfCharacter(from: .letters) == nil, "\(file.lastPathComponent): verbatim words: \(stripped)")
            }
        }
    }

    @Test("Catalog entries are English source text and complete", arguments: modules.map(\.name))
    func catalogHealth(moduleName: String) throws {
        let module = try #require(Self.modules.first { $0.name == moduleName })
        for path in module.catalogs {
            let data = try Data(contentsOf: Self.url(path))
            let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["sourceLanguage"] as? String == "en", "\(path): source language must be en")
            let strings = try #require(json["strings"] as? [String: Any])
            #expect(!strings.isEmpty)
            for (key, value) in strings {
                let entry = try #require(value as? [String: Any])
                #expect(entry["extractionState"] as? String != "stale", "\(path): stale key \(key)")
                guard let localizations = entry["localizations"] as? [String: Any],
                      let en = localizations["en"] as? [String: Any] else { continue }
                // Düz metin dolu olmalı; çoğul varyasyonda one ve other bulunmalı.
                if let unit = en["stringUnit"] as? [String: Any] {
                    #expect((unit["value"] as? String)?.isEmpty == false, "\(path): empty en value for \(key)")
                    #expect(unit["state"] as? String != "new", "\(path): untranslated en value for \(key)")
                }
                let plurals = (en["variations"] as? [String: Any])?["plural"] as? [String: Any]
                    ?? (en["substitutions"] as? [String: Any])?.values.compactMap {
                        (($0 as? [String: Any])?["variations"] as? [String: Any])?["plural"] as? [String: Any]
                    }.first
                if let en = localizations["en"] as? [String: Any],
                   en["variations"] != nil || en["substitutions"] != nil {
                    let forms = try #require(plurals, "\(path): \(key) has variations without plural")
                    #expect(forms["one"] != nil && forms["other"] != nil, "\(path): \(key) needs one and other")
                }
            }
        }
    }

    @Test("Plural-sensitive texts have plural variations in the catalog", arguments: [
        "^[%lld payment](inflect: true)",
        "^[%lld month](inflect: true) remaining",
        "In %lld days",
        "%lld payments due today, %@ total",
        "%lld payments due tomorrow, %@ total",
    ])
    func pluralKeysHaveVariations(key: String) throws {
        let strings = try Self.catalog(at: Self.modules[0].catalogs[0])
        let entry = try #require(strings[key] as? [String: Any], "missing key \(key)")
        let en = try #require((entry["localizations"] as? [String: Any])?["en"] as? [String: Any])
        #expect(en["variations"] != nil || en["substitutions"] != nil, "\(key) has no plural variation")
    }

    @Test("English texts that UI tests match on still exist in the catalog", arguments: [
        "Design gallery", "Version %@",
    ])
    func uiTestTextsExist(key: String) throws {
        let strings = try Self.catalog(at: Self.modules[0].catalogs[0])
        #expect(strings[key] != nil, "UI tests look for \(key)")
    }
}
