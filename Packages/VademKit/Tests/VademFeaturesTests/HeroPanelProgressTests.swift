import Foundation
import SwiftUI
import Testing
import VademCore
@testable import VademFeatures

@Suite("HeroPanel.progress")
struct HeroPanelProgressTests {

    private static func money(_ text: String) -> Money { Money(Decimal(string: text)!) }

    // Beklenen değerler kabul ölçütlerinden elle hesaplandı: paid / total, 0...1 aralığına sıkıştırılmış.
    @Test("Computes the clamped paid share", arguments: [
        // (paid, total, beklenen)
        ("0", "0", 0.0),            // toplam 0 → 0
        ("100", "0", 0.0),          // toplam 0, ödenen var → yine 0
        ("0", "-50", 0.0),          // negatif toplam → 0
        ("50", "-100", 0.0),
        ("150", "100", 1.0),        // fazla ödeme → 1
        ("100", "100", 1.0),        // tam ödeme → 1
        ("1000000", "1", 1.0),
        ("-10", "100", 0.0),        // negatif ödenen → 0
        ("-200", "100", 0.0),
        ("0", "100", 0.0),
        ("50", "100", 0.5),         // tipik oran
        ("1", "4", 0.25),
        ("1200", "4800", 0.25),
        ("0.01", "100", 0.0001),    // kuruş hassasiyeti
        ("1", "3", 1.0 / 3.0),
        ("99.99", "100", 0.9999),   // 1'in hemen altı 1'e yuvarlanmaz
    ])
    func progress(paid: String, total: String, expected: Double) {
        let value = HeroPanel<EmptyView>.progress(paid: Self.money(paid), total: Self.money(total))
        #expect(abs(value - expected) < 1e-9)
        #expect((0.0...1.0).contains(value))
    }

    // Okunan özet: başlık, toplam, "Paid X of Y"; beklenenler elle yazıldı.
    @Test("Summary reads title, total and paid share")
    func summaryTypical() {
        let label = HeroPanel<EmptyView>.accessibilitySummary(
            title: "This month", paid: Self.money("1200"), total: Self.money("4825.50"))
        #expect(label == "This month, 4.825,50 Türk lirası, Paid 1.200,00 Türk lirası of 4.825,50 Türk lirası")
    }

    @Test("Summary with nothing paid reads zero")
    func summaryZeroPaid() {
        let label = HeroPanel<EmptyView>.accessibilitySummary(
            title: "This month", paid: Self.money("0"), total: Self.money("350"))
        #expect(label == "This month, 350,00 Türk lirası, Paid 0,00 Türk lirası of 350,00 Türk lirası")
    }

    @Test("Summary never contains the lira symbol", arguments: [("0", "0"), ("1200", "4825.50"), ("99.99", "100")])
    func summaryHasNoLiraSymbol(paid: String, total: String) {
        let label = HeroPanel<EmptyView>.accessibilitySummary(
            title: "This month", paid: Self.money(paid), total: Self.money(total))
        #expect(!label.contains("₺"))
    }
}
