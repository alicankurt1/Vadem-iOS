import Foundation
import Testing
import VademCore
import VademFeatures

@Suite("AmountText.spokenLabel")
struct AmountSpokenLabelTests {

    // Beklenenler sözleşmeden türetildi: "₺" yok, sayı tr_TR biçiminde, sonuna " Türk lirası",
    // negatifte başa "eksi ".
    @Test("Speaks the amount without the lira symbol", arguments: [
        // Sözleşme örnekleri
        ("1234.56", "1.234,56 Türk lirası"),
        ("-5", "eksi 5,00 Türk lirası"),
        // Sıfır, milyon, kuruş
        ("0", "0,00 Türk lirası"),
        ("1000000", "1.000.000,00 Türk lirası"),
        ("0.05", "0,05 Türk lirası"),
        // Büyük negatif
        ("-1234567.89", "eksi 1.234.567,89 Türk lirası"),
        ("-999999999999.99", "eksi 999.999.999.999,99 Türk lirası"),
        // Yuvarlama: Money kuruşa yuvarlar; sıfıra yuvarlanan negatif "eksi" almamalı
        ("1.005", "1,01 Türk lirası"),
        ("-0.001", "0,00 Türk lirası"),
    ])
    func spokenLabel(input: String, expected: String) throws {
        let amount = try #require(Decimal(string: input, locale: Locale(identifier: "en_US_POSIX")))
        #expect(AmountText.spokenLabel(Money(amount)) == expected)
    }

    @Test("Spoken label never contains the lira symbol")
    func noSymbol() {
        for value in [Decimal(0), 5, -5, Decimal(string: "1234.56")!] {
            #expect(!AmountText.spokenLabel(Money(value)).contains("₺"))
        }
    }
}
