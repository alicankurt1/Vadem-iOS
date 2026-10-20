import Foundation
import SwiftUI
import Testing
import VademFeatures

@Suite("Color tokens")
struct ColorTokenTests {

    /// Issue tablosu: token → (açık, koyu). Değerler issue'dan kopyalandı.
    static let table: [(name: String, light: String, dark: String)] = [
        ("background", "F7F6F3", "0B0D14"),
        ("surface", "FFFFFF", "151824"),
        ("separator", "E4E2DC", "1E2232"),
        ("textPrimary", "14161F", "F3F4F8"),
        ("textSecondary", "5B6070", "A1A7B8"),
        ("brand", "4338CA", "A5B4FC"),
        ("dueToday", "991B1B", "FCA5A5"),
        ("dueTodayBackground", "FDECEC", "3B1515"),
        ("dueSoon", "92400E", "FCD34D"),
        ("dueSoonBackground", "FEF3C7", "3A2A0B"),
        ("dueLater", "3F4352", "C3C8D6"),
        ("dueLaterBackground", "EDECE8", "1E2232"),
        ("paid", "0F766E", "5EEAD4"),
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
