import Foundation
import SwiftUI
import Testing
import VademFeatures

@Suite("Color tokens")
struct ColorTokenTests {

    /// Issue tablosu: token → (açık, koyu). Değerler issue'dan kopyalandı.
    static let table: [(name: String, light: String, dark: String)] = [
        ("background", "EAF7F5", "06161A"),
        ("surface", "FFFFFF", "0D2429"),
        ("separator", "CFE5E2", "143238"),
        ("hero", "0F766E", "0F3A40"),
        ("heroText", "FFFFFF", "E8FAF8"),
        ("heroSecondary", "CCFBF1", "9CC5C2"),
        ("accent", "5EEAD4", "2DE2C8"),
        ("onAccent", "06302C", "06161A"),
        ("textPrimary", "06262A", "E8FAF8"),
        ("textSecondary", "3F6368", "9CC5C2"),
        ("brand", "0B5F58", "5EEAD4"),
        ("dueToday", "B42318", "FDA29B"),
        ("dueTodayBackground", "FEE4E2", "3B1420"),
        ("dueSoon", "93370D", "FEC84B"),
        ("dueSoonBackground", "FEF0C7", "3A2A05"),
        ("dueLater", "3F6368", "A9D3D0"),
        ("dueLaterBackground", "D5EFEC", "143238"),
        ("paid", "067647", "6CE9A6"),
        ("ambientHome", "CDEFEA", "0B2D30"),
        ("ambientAnalytics", "E3E5FB", "181B3A"),
        ("ambientCards", "FBE3D3", "2C1813"),
        ("ambientSettings", "D9E9F8", "0D2238"),
    ]

    @Test("ColorToken has exactly the tokens in the issue table")
    func tokenNames() {
        #expect(Set(ColorToken.allCases.map(\.rawValue)) == Set(Self.table.map(\.name)))
        #expect(ColorToken.allCases.count == Self.table.count)
    }

    @Test("Every token is exposed as a Color static")
    func colorStatics() {
        // Derlenmesi yeterli: her token için `Color.vademX` kısa adı var olmalı.
        let statics: [Color] = [
            .vademBackground, .vademSurface, .vademSeparator, .vademTextPrimary, .vademTextSecondary,
            .vademBrand, .vademDueToday, .vademDueTodayBackground, .vademDueSoon, .vademDueSoonBackground,
            .vademDueLater, .vademDueLaterBackground, .vademPaid,
            .vademHero, .vademHeroText, .vademHeroSecondary, .vademAccent, .vademOnAccent,
            .vademAmbientHome, .vademAmbientAnalytics, .vademAmbientCards, .vademAmbientSettings,
        ]
        #expect(statics.count == Self.table.count)
    }

    // `swift test` asset kataloğunu derlemez (ham .xcassets kopyalanır), bu yüzden renkler
    // çalışma anında değil, kaynak katalogdaki Contents.json üzerinden doğrulanır.
    @Test("Each color set has the issue's light and dark value", arguments: table.map(\.name))
    func colorSetValues(name: String) throws {
        let entry = try #require(Self.table.first { $0.name == name })
        let url = Self.catalogURL.appending(path: "\(name).colorset/Contents.json")
        let data = try Data(contentsOf: url)
        let json = try JSONDecoder().decode(ColorSet.self, from: data)

        let light = json.colors.filter { !$0.isDark }
        let dark = json.colors.filter(\.isDark)
        #expect(light.count == 1, "\(name): expected one light (any) entry")
        #expect(dark.count == 1, "\(name): expected one dark entry")
        #expect(try light.first?.hex() == entry.light, "\(name) light")
        #expect(try dark.first?.hex() == entry.dark, "\(name) dark")
        for color in json.colors {
            #expect(color.color.colorSpace == "srgb", "\(name): tokens are sRGB hex values")
            #expect(Double(color.color.components.alpha) == 1, "\(name): tokens are opaque")
        }
    }

    // MARK: - Katalog okuma

    static let catalogURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/VademFeatures/Resources/Colors.xcassets")

    struct ColorSet: Decodable {
        let colors: [Entry]
    }

    struct Entry: Decodable {
        struct Appearance: Decodable {
            let appearance: String
            let value: String
        }
        struct Value: Decodable {
            let colorSpace: String
            let components: Components
            enum CodingKeys: String, CodingKey {
                case colorSpace = "color-space"
                case components
            }
        }
        struct Components: Decodable {
            let red: String
            let green: String
            let blue: String
            let alpha: String
        }

        let appearances: [Appearance]?
        let color: Value

        var isDark: Bool {
            appearances?.contains { $0.appearance == "luminosity" && $0.value == "dark" } ?? false
        }

        /// Bileşenleri "RRGGBB" olarak verir; katalog "0x43" ya da "0.263" biçiminde yazabilir.
        func hex() throws -> String {
            try [color.components.red, color.components.green, color.components.blue]
                .map { String(format: "%02X", try Self.byte($0)) }
                .joined()
        }

        static func byte(_ component: String) throws -> Int {
            if component.lowercased().hasPrefix("0x") {
                return try #require(Int(component.dropFirst(2), radix: 16))
            }
            let value = try #require(Double(component))
            // 0...1 kesirli değer ya da 0...255 tam sayı olabilir.
            return value <= 1 && component.contains(".") ? Int((value * 255).rounded()) : Int(value)
        }
    }
}
