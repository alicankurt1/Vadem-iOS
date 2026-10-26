import Foundation
import Testing

// Repo dosyalarını denetler: uygulama ikonu, sürüm ayarları, App Store metni.
// Repo kökü #filePath'ten bulunur (Packages/VademKit/Tests/VademCoreTests/ -> 5 seviye yukarı).
private enum Repo {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static func url(_ path: String) -> URL { root.appendingPathComponent(path) }

    static func text(_ path: String) throws -> String {
        try String(contentsOf: url(path), encoding: .utf8)
    }
}

@Suite("App icon")
struct AppIconTests {
    private static let setPath = "Vadem/Assets.xcassets/AppIcon.appiconset"

    private struct Slot {
        let name: String
        let filename: String
        let appearance: String?
    }

    private static func slots() throws -> [Slot] {
        let data = try Data(contentsOf: Repo.url("\(setPath)/Contents.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let images = try #require(json["images"] as? [[String: Any]], "Contents.json has no images array")
        return images.map { image in
            let appearances = image["appearances"] as? [[String: String]]
            let value = appearances?.first?["value"]
            return Slot(
                name: value ?? "default",
                filename: image["filename"] as? String ?? "",
                appearance: value
            )
        }
    }

    private struct PNGInfo {
        var width: Int
        var height: Int
        var colorType: UInt8
        var hasTransparencyChunk: Bool
    }

    private static func readPNG(_ url: URL) throws -> PNGInfo {
        let d = [UInt8](try Data(contentsOf: url))
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        try #require(d.count > 33 && Array(d[0..<8]) == signature, "\(url.lastPathComponent) is not a PNG")
        func be32(_ i: Int) -> Int {
            (Int(d[i]) << 24) | (Int(d[i + 1]) << 16) | (Int(d[i + 2]) << 8) | Int(d[i + 3])
        }
        // IHDR: genişlik 16, yükseklik 20, renk tipi 25. Sonra chunk'ları gez (tRNS ara).
        var hasTRNS = false
        var offset = 8
        while offset + 8 <= d.count {
            let length = be32(offset)
            let type = String(decoding: d[(offset + 4)..<(offset + 8)], as: UTF8.self)
            if type == "tRNS" { hasTRNS = true }
            if type == "IDAT" || type == "IEND" { break }
            offset += 12 + length
        }
        return PNGInfo(width: be32(16), height: be32(20), colorType: d[25], hasTransparencyChunk: hasTRNS)
    }

    @Test("Has default, dark and tinted 1024x1024 slots")
    func hasThreeSlots() throws {
        let slots = try Self.slots()
        let names = Set(slots.map(\.name))
        #expect(names == ["default", "dark", "tinted"], "Icon slots are \(names.sorted()); expected default, dark, tinted")
        #expect(slots.count == 3, "Expected exactly 3 slots, found \(slots.count)")
        let data = try Data(contentsOf: Repo.url("\(Self.setPath)/Contents.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for image in try #require(json["images"] as? [[String: Any]]) {
            #expect(image["size"] as? String == "1024x1024", "Slot \(image["filename"] ?? "?") must declare size 1024x1024")
        }
    }

    @Test("Every slot references an existing, truly 1024x1024 PNG", arguments: ["default", "dark", "tinted"])
    func pngIsValid(slotName: String) throws {
        let slot = try #require(try Self.slots().first { $0.name == slotName }, "No \(slotName) slot")
        #expect(!slot.filename.isEmpty, "\(slotName) slot has no filename")
        let url = Repo.url("\(Self.setPath)/\(slot.filename)")
        try #require(FileManager.default.fileExists(atPath: url.path), "\(slot.filename) is missing for the \(slotName) slot")
        let png = try Self.readPNG(url)
        #expect(png.width == 1024 && png.height == 1024, "\(slot.filename) is \(png.width)x\(png.height), expected 1024x1024")
    }

    @Test("Default and dark icons have no alpha channel", arguments: ["default", "dark"])
    func noAlpha(slotName: String) throws {
        let slot = try #require(try Self.slots().first { $0.name == slotName }, "No \(slotName) slot")
        let png = try Self.readPNG(Repo.url("\(Self.setPath)/\(slot.filename)"))
        // Renk tipi 4 (gri+alfa) ve 6 (RGBA) alfa kanalı taşır.
        #expect(png.colorType != 4 && png.colorType != 6, "\(slot.filename) has an alpha channel (PNG color type \(png.colorType))")
        #expect(!png.hasTransparencyChunk, "\(slot.filename) has a tRNS transparency chunk")
    }

    @Test("Slots use three different image files")
    func distinctFiles() throws {
        let files = try Self.slots().map(\.filename)
        #expect(Set(files).count == 3, "Slots share image files: \(files)")
    }
}

@Suite("Version settings")
struct VersionSettingsTests {
    @Test("Shared.xcconfig defines the version and build number", arguments: ["MARKETING_VERSION", "CURRENT_PROJECT_VERSION"])
    func xcconfigDefines(key: String) throws {
        let lines = try Repo.text("Config/Shared.xcconfig").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let line = lines.first { !$0.hasPrefix("//") && $0.hasPrefix(key) && $0.dropFirst(key.count).trimmingCharacters(in: .whitespaces).hasPrefix("=") }
        let value = line?.split(separator: "=", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? ""
        #expect(line != nil, "\(key) is not defined in Config/Shared.xcconfig")
        #expect(!value.isEmpty, "\(key) has an empty value in Config/Shared.xcconfig")
    }

    @Test("Marketing version is 1.0")
    func marketingVersion() throws {
        let text = try Repo.text("Config/Shared.xcconfig")
        #expect(text.contains("MARKETING_VERSION = 1.0"), "Issue requires marketing version 1.0")
    }

    @Test("project.pbxproj has no version overrides", arguments: ["MARKETING_VERSION", "CURRENT_PROJECT_VERSION"])
    func pbxprojHasNoOverrides(key: String) throws {
        let hits = try Repo.text("Vadem.xcodeproj/project.pbxproj").split(separator: "\n").filter { $0.contains(key) }
        #expect(hits.isEmpty, "project.pbxproj overrides \(key): \(hits.map { $0.trimmingCharacters(in: .whitespaces) })")
    }
}

@Suite("App Store listing")
struct AppStoreListingTests {
    private static func doc() throws -> String { try Repo.text("docs/app-store.md") }

    /// "## " başlığının altındaki gövde (sonraki "## " başlığına kadar).
    private static func section(_ title: String) throws -> String {
        let lines = try doc().components(separatedBy: "\n")
        let start = try #require(lines.firstIndex { $0.hasPrefix("## ") && $0.lowercased().contains(title.lowercased()) },
                                 "docs/app-store.md has no '## …\(title)…' section")
        let rest = lines[(start + 1)...]
        let end = rest.firstIndex { $0.hasPrefix("## ") } ?? lines.endIndex
        return lines[(start + 1)..<end].joined(separator: "\n")
    }

    /// Satırdaki ilk `...` kod parçasının içeriği.
    private static func codeSpans(in line: String) -> [String] {
        line.components(separatedBy: "`").enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
    }

    @Test("Has every required section", arguments: [
        "Name and subtitle", "Description", "Keywords", "Screenshot plan", "Age rating", "privacy", "URLs"
    ])
    func hasSection(title: String) throws {
        let body = try Self.section(title)
        #expect(!body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Section '\(title)' is empty")
    }

    @Test("Description has English and Turkish texts")
    func descriptionLanguages() throws {
        let body = try Self.section("Description")
        #expect(body.contains("English"), "Description section lacks an English text")
        #expect(body.contains("Turkish"), "Description section lacks a Turkish text")
        #expect(body.components(separatedBy: "```").count >= 5, "Expected two fenced description texts")
    }

    @Test("Subtitle is at most 30 characters in English and Turkish")
    func subtitleLength() throws {
        let row = try #require(try Self.section("Name and subtitle").components(separatedBy: "\n").first { $0.contains("Subtitle") },
                               "No Subtitle row in name table")
        let spans = Self.codeSpans(in: row)
        try #require(spans.count >= 2, "Subtitle row should hold an English and a Turkish `text`; found \(spans)")
        for subtitle in spans.prefix(2) {
            #expect(!subtitle.isEmpty && subtitle.count <= 30, "Subtitle '\(subtitle)' is \(subtitle.count) characters (limit 30)")
        }
    }

    @Test("Name is at most 30 characters")
    func nameLength() throws {
        let row = try #require(try Self.section("Name and subtitle").components(separatedBy: "\n").first { $0.contains("| Name") })
        for name in Self.codeSpans(in: row).prefix(2) {
            #expect(name.count <= 30, "Name '\(name)' is \(name.count) characters (limit 30)")
        }
    }

    @Test("Keywords are at most 100 characters for English and Turkish", arguments: ["English", "Turkish"])
    func keywordsLength(language: String) throws {
        let line = try #require(try Self.section("Keywords").components(separatedBy: "\n").first { $0.contains(language) && $0.contains("`") },
                                "No \(language) keywords line")
        let keywords = try #require(Self.codeSpans(in: line).first, "No `keywords` code span in \(language) line")
        #expect(keywords.count <= 100, "\(language) keywords are \(keywords.count) characters (limit 100)")
        #expect(keywords.count >= 20, "\(language) keywords look too short (\(keywords.count))")
        #expect(!keywords.contains(", "), "\(language) keywords waste characters on spaces after commas")
    }

    @Test("Screenshot plan lists device sizes and light/dark")
    func screenshotPlan() throws {
        let body = try Self.section("Screenshot plan").lowercased()
        #expect(body.contains("iphone"), "Screenshot plan names no iPhone size")
        #expect(body.contains("ipad"), "Screenshot plan names no iPad size")
        #expect(body.contains("light") && body.contains("dark"), "Screenshot plan must cover light and dark")
    }

    @Test("Age rating section answers questions in a table")
    func ageRating() throws {
        let rows = try Self.section("Age rating").components(separatedBy: "\n").filter { $0.hasPrefix("|") }
        #expect(rows.count >= 5, "Age rating should be a table of answers; found \(rows.count) rows")
    }

    @Test("Support and privacy URLs are placeholders, not real links")
    func urlPlaceholders() throws {
        let body = try Self.section("URLs")
        #expect(body.contains("Support URL"), "No Support URL row")
        #expect(body.contains("Privacy Policy URL"), "No Privacy Policy URL row")
        #expect(!body.contains("http://") && !body.contains("https://"), "URL section should hold placeholders only (no real links)")
    }

    @Test("Privacy label matches PrivacyInfo.xcprivacy: no tracking, no collected data")
    func privacyLabelMatchesManifest() throws {
        let data = try Data(contentsOf: Repo.url("Vadem/PrivacyInfo.xcprivacy"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let tracking = plist["NSPrivacyTracking"] as? Bool
        let collected = plist["NSPrivacyCollectedDataTypes"] as? [Any]
        #expect(tracking == false, "Manifest must declare NSPrivacyTracking = false")
        #expect(collected?.isEmpty == true, "Manifest must declare no collected data types")

        let label = try Self.section("privacy").lowercased()
        #expect(label.contains("data not collected"), "Privacy label must resolve to 'Data Not Collected'")
        #expect(label.contains("tracking:** no") || label.contains("tracking: no"), "Privacy label must say tracking is No")
        #expect(label.contains("do not collect data") || label.contains("not collect"), "Privacy label must state data is not collected")
        #expect(!label.contains("tracking:** yes"), "Privacy label claims tracking")
    }
}
