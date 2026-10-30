import Foundation
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
        // Ortam arka planı (#209): metin renkleri her sekmenin tonu üzerinde AA'yı korur.
        Pair(foreground: "textPrimary", background: "ambientHome"),
        Pair(foreground: "textSecondary", background: "ambientHome"),
        Pair(foreground: "brand", background: "ambientHome"),
        Pair(foreground: "paid", background: "ambientHome"),
        Pair(foreground: "textPrimary", background: "ambientAnalytics"),
        Pair(foreground: "textSecondary", background: "ambientAnalytics"),
        Pair(foreground: "brand", background: "ambientAnalytics"),
        Pair(foreground: "paid", background: "ambientAnalytics"),
        Pair(foreground: "textPrimary", background: "ambientCards"),
        Pair(foreground: "textSecondary", background: "ambientCards"),
        Pair(foreground: "brand", background: "ambientCards"),
        Pair(foreground: "paid", background: "ambientCards"),
        Pair(foreground: "textPrimary", background: "ambientSettings"),
        Pair(foreground: "textSecondary", background: "ambientSettings"),
        Pair(foreground: "brand", background: "ambientSettings"),
        Pair(foreground: "paid", background: "ambientSettings"),
        Pair(foreground: "dueToday", background: "ambientHome"),
        Pair(foreground: "dueSoon", background: "ambientHome"),
        Pair(foreground: "dueLater", background: "ambientHome"),
        Pair(foreground: "dueToday", background: "ambientAnalytics"),
        Pair(foreground: "dueSoon", background: "ambientAnalytics"),
        Pair(foreground: "dueLater", background: "ambientAnalytics"),
        Pair(foreground: "dueToday", background: "ambientCards"),
        Pair(foreground: "dueSoon", background: "ambientCards"),
        Pair(foreground: "dueLater", background: "ambientCards"),
        Pair(foreground: "dueToday", background: "ambientSettings"),
        Pair(foreground: "dueSoon", background: "ambientSettings"),
        Pair(foreground: "dueLater", background: "ambientSettings"),
    ]

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
