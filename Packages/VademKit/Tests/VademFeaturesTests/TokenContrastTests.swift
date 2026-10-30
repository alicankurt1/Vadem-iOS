import Foundation
import SwiftUI
import Testing
@testable import VademFeatures

/// Token çiftlerinin WCAG 2.x kontrastı (#59). UI check'in kontrast denetimi gradyan ve yarı saydam
/// zeminlerde koşudan koşuya değiştiği için orada sadece not olarak raporlanır; düz zemindeki
/// token çiftlerinin kontrastı burada hesapla güvence altına alınır.
@Suite("Token pair contrast")
struct TokenContrastTests {

    /// Bir ön plan token'ının oturduğu zemin token'ı.
    struct Pair: Sendable, CustomTestStringConvertible {
        let foreground: String
        let background: String
        var testDescription: String { "\(foreground) on \(background)" }
    }

    // DueChip.Kind çiftleri (overdue, today ile aynı çifti kullanır) ve metin/vurgu renklerinin
    // oturduğu düz zeminler.
    static let pairs: [Pair] = [
        Pair(foreground: "dueToday", background: "dueTodayBackground"),
        Pair(foreground: "dueToday", background: "surface"),  // Silme satırı (#88)
        Pair(foreground: "dueSoon", background: "dueSoonBackground"),
        Pair(foreground: "dueLater", background: "dueLaterBackground"),
        // Analytics çubuk grafiğinde tek seferlik ödeme serisi (#191); grafik düz zeminde çizilir.
        Pair(foreground: "dueSoon", background: "background"),
        Pair(foreground: "dueSoon", background: "surface"),
        Pair(foreground: "textPrimary", background: "background"),
        Pair(foreground: "textPrimary", background: "surface"),
        Pair(foreground: "textSecondary", background: "background"),
        Pair(foreground: "textSecondary", background: "surface"),
        Pair(foreground: "brand", background: "background"),
        Pair(foreground: "brand", background: "surface"),
        Pair(foreground: "paid", background: "background"),
        Pair(foreground: "paid", background: "surface"),
        Pair(foreground: "heroText", background: "hero"),
        Pair(foreground: "heroSecondary", background: "hero"),
        Pair(foreground: "onAccent", background: "accent"),
    ]

    // MARK: - Cam yüzey karışımı (#211)

    /// Cam yüzeyde bir ön plan token'ı, örtü rengi ve altından görünen zemin.
    struct GlassCase: Sendable, CustomTestStringConvertible {
        let foreground: String
        let veil: String
        let opacity: Double
        var testDescription: String { "\(foreground) on \(veil) veil @\(opacity)" }
    }

    static let glassCases: [GlassCase] = [
        GlassCase(foreground: "textPrimary", veil: "surface", opacity: GlassSurfaceModifier<Capsule>.surfaceOpacity),
        GlassCase(foreground: "textSecondary", veil: "surface", opacity: GlassSurfaceModifier<Capsule>.surfaceOpacity),
        GlassCase(foreground: "onAccent", veil: "accent", opacity: GlassSurfaceModifier<Capsule>.tintOpacity),
    ]

    /// Örtünün altında görünebilecek en kötü zeminler: ekran zemini, hero ve saf siyah/beyaz.
    static let backdrops: [String] = ["background", "hero", "black", "white"]

    @Test("Glass veil constants are valid opacities")
    func glassOpacitiesAreValid() {
        for value in [GlassSurfaceModifier<Capsule>.surfaceOpacity, GlassSurfaceModifier<Capsule>.tintOpacity] {
            #expect(value > 0 && value <= 1)
        }
    }

    @Test("Text on blended glass surface meets WCAG AA (4.5:1) over worst-case backdrops", arguments: glassCases)
    func glassBlendContrast(glass: GlassCase) throws {
        for (mode, dark) in [("light", false), ("dark", true)] {
            let foreground = try Self.hex(glass.foreground, dark: dark)
            let veil = try Self.hex(glass.veil, dark: dark)
            for backdropName in Self.backdrops {
                let backdrop: UInt32
                switch backdropName {
                case "black": backdrop = 0x000000
                case "white": backdrop = 0xFFFFFF
                default: backdrop = try Self.hex(backdropName, dark: dark)
                }
                let blended = Self.blend(veil, over: backdrop, alpha: glass.opacity)
                let ratio = CardContrastTests.contrast(foreground, blended)
                #expect(
                    ratio >= 4.5,
                    "\(glass.testDescription) over \(backdropName) (\(mode)): contrast \(String(format: "%.2f", ratio)) < 4.5"
                )
            }
        }
    }

    /// `top` rengini `alpha` ile `bottom` üzerine karıştırır (kanal başına doğrusal).
    static func blend(_ top: UInt32, over bottom: UInt32, alpha: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let t = Double((top >> shift) & 0xFF)
            let b = Double((bottom >> shift) & 0xFF)
            return UInt32((t * alpha + b * (1 - alpha)).rounded()) & 0xFF
        }
        return channel(16) << 16 | channel(8) << 8 | channel(0)
    }

    @Test("Pair meets WCAG AA (4.5:1) in light and dark", arguments: pairs)
    func pairContrast(pair: Pair) throws {
        for (mode, dark) in [("light", false), ("dark", true)] {
            let foreground = try Self.hex(pair.foreground, dark: dark)
            let background = try Self.hex(pair.background, dark: dark)
            let ratio = CardContrastTests.contrast(foreground, background)
            #expect(
                ratio >= 4.5,
                "\(pair.testDescription) (\(mode)): contrast \(String(format: "%.2f", ratio)) < 4.5"
            )
        }
    }

    // Tablo adı yanlış yazılırsa test sessizce atlanmasın.
    @Test("Every pair names tokens that exist")
    func pairsNameKnownTokens() {
        let names = Set(ColorTokenTests.table.map(\.name))
        for pair in Self.pairs {
            #expect(names.contains(pair.foreground), "unknown token \(pair.foreground)")
            #expect(names.contains(pair.background), "unknown token \(pair.background)")
        }
    }

    // MARK: - Tablo okuma

    static func hex(_ token: String, dark: Bool) throws -> UInt32 {
        let row = try #require(ColorTokenTests.table.first { $0.name == token })
        return try #require(UInt32(dark ? row.dark : row.light, radix: 16))
    }
}
