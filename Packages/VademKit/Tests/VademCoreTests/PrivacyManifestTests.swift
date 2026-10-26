import Foundation
import Testing

// Gizlilik manifestlerini ve politika metnini repo kökünden okuyup doğrular.
// Dosyalar paketin dışında olduğu için yol #filePath üzerinden türetilir.
@Suite("Privacy manifests and policy")
struct PrivacyManifestTests {
    /// Repo kökü: .../Packages/VademKit/Tests/VademCoreTests/<dosya> -> 5 seviye yukarı.
    private static var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    private static let manifestPaths = [
        "Vadem/PrivacyInfo.xcprivacy",
        "VademWidget/PrivacyInfo.xcprivacy",
    ]

    /// Apple'ın belgelediği required-reason API kategorileri ve geçerli neden kodları.
    private static let validReasons: [String: Set<String>] = [
        "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1", "1C8F.1", "C56D.1", "AC6B.1"],
        "NSPrivacyAccessedAPICategoryFileTimestamp": ["DDA9.1", "C617.1", "3B52.1", "0A2A.1"],
        "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1", "8FFB.1", "3D61.1"],
        "NSPrivacyAccessedAPICategoryDiskSpace": ["85F4.1", "E174.1", "7D9E.1", "B728.1"],
        "NSPrivacyAccessedAPICategoryActiveKeyboards": ["3EC4.1", "54BD.1"],
    ]

    private static func loadManifest(_ relativePath: String) throws -> [String: Any] {
        let url = repoRoot.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any])
    }

    @Test("Manifest declares no tracking", arguments: manifestPaths)
    func noTracking(path: String) throws {
        let manifest = try Self.loadManifest(path)
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        let domains = try #require(manifest["NSPrivacyTrackingDomains"] as? [Any])
        #expect(domains.isEmpty)
    }

    @Test("Manifest declares no collected data types", arguments: manifestPaths)
    func noCollectedData(path: String) throws {
        let manifest = try Self.loadManifest(path)
        let collected = try #require(manifest["NSPrivacyCollectedDataTypes"] as? [Any])
        #expect(collected.isEmpty)
    }

    @Test("Accessed API entries have a known category and valid reasons", arguments: manifestPaths)
    func accessedAPIsAreValid(path: String) throws {
        let manifest = try Self.loadManifest(path)
        let entries = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        for entry in entries {
            let category = try #require(entry["NSPrivacyAccessedAPIType"] as? String)
            let allowed = try #require(Self.validReasons[category], "Unknown category \(category)")
            let reasons = try #require(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
            #expect(!reasons.isEmpty, "No reasons for \(category)")
            for reason in reasons {
                #expect(allowed.contains(reason), "\(reason) is not valid for \(category)")
            }
        }
    }

    // UserDefaults gerçekten kullanılıyor (UserDefaultsReminderPreferencesStore);
    // widget da VademFeatures'ı bağladığı için aynı beyanı taşımalı.
    @Test("Manifest declares the UserDefaults API category", arguments: manifestPaths)
    func declaresUserDefaults(path: String) throws {
        let manifest = try Self.loadManifest(path)
        let entries = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let categories = entries.compactMap { $0["NSPrivacyAccessedAPIType"] as? String }
        #expect(categories.contains("NSPrivacyAccessedAPICategoryUserDefaults"))
    }

    // İletişim yer tutucusu her dilde bir kez geçer (İngilizce + Türkçe = 2);
    // sahibi doldurana kadar yer tutucu silinmemeli, çoğaltılmamalı.
    @Test("Privacy policy has the contact placeholder once per language")
    func policyContactPlaceholder() throws {
        let url = Self.repoRoot.appendingPathComponent("docs/privacy.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        let placeholder = "[contact email — owner to fill in]"
        let turkishRange = try #require(text.range(of: "## Türkçe"))
        let english = text[..<turkishRange.lowerBound]
        let turkish = text[turkishRange.lowerBound...]
        #expect(english.components(separatedBy: placeholder).count - 1 == 1)
        #expect(turkish.components(separatedBy: placeholder).count - 1 == 1)
    }

    @Test("Privacy policy has English and Turkish sections")
    func policyHasBothLanguages() throws {
        let url = Self.repoRoot.appendingPathComponent("docs/privacy.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("## English"))
        #expect(text.contains("## Türkçe"))
    }
}
