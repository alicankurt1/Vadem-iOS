import Foundation
import Testing
import VademCore
import VademFeatures

@Suite("AmountText.format")
struct AmountFormatTests {

    // Tutarlar `Decimal(string:)` ile kurulur; `Double` üzerinden geçmez.
    @Test("Formats Turkish lira in tr_TR style", arguments: [
        // Issue örnekleri
        ("0", "₺0,00"),
        ("1234.56", "₺1.234,56"),
        ("-5", "-₺5,00"),
        ("1000000", "₺1.000.000,00"),
        // Küçük tutarlar ve ondalık dolgusu
        ("0.01", "₺0,01"),
        ("0.5", "₺0,50"),
        ("-0.01", "-₺0,01"),
        // Binlik ayırıcı sınırı
        ("999", "₺999,00"),
        ("1000", "₺1.000,00"),
        ("-1234.56", "-₺1.234,56"),
        // Kuruş yuvarlama (Money yarımı sıfırdan uzağa yuvarlar), gösterim yuvarlanmış değeri yazar
        ("1.005", "₺1,01"),
        ("1.004", "₺1,00"),
        ("999.995", "₺1.000,00"),
        ("-1234.565", "-₺1.234,57"),
        // Sıfıra yuvarlanan negatif tutar "-₺0,00" olmamalı
        ("-0.001", "₺0,00"),
        // Büyük tutarlar: Double'a çevrilse hassasiyet kaybolurdu
        ("12345678901.23", "₺12.345.678.901,23"),
        ("999999999999999.99", "₺999.999.999.999.999,99"),
        ("-1000000000000", "-₺1.000.000.000.000,00"),
    ])
    func format(input: String, expected: String) throws {
        let amount = try #require(Decimal(string: input, locale: Locale(identifier: "en_US_POSIX")))
        #expect(AmountText.format(Money(amount)) == expected)
    }

    @Test("Zero constant formats like zero")
    func zeroConstant() {
        #expect(AmountText.format(.zero) == "₺0,00")
    }
}
