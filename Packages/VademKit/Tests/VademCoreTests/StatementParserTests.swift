import Foundation
import Testing

@testable import VademCore

// Anonim, uydurma ekstre metinleri; gerçek banka, kart no ya da kişisel veri yok.
@Suite("StatementParser")
struct StatementParserTests {
    /// Compares only the meaningful fields (ids are random).
    struct Expected: Sendable, CustomTestStringConvertible {
        let merchant: String
        let amount: Decimal
        let current: Int
        let total: Int
        let date: StatementDate?
        var testDescription: String { "\(merchant) \(current)/\(total) \(amount)" }
    }

    private static func day(_ d: Int, _ m: Int, _ y: Int) -> StatementDate? {
        StatementDate(year: y, month: m, day: d)
    }

    private static func dec(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

    private func check(_ got: [InstallmentCandidate], _ want: [Expected], sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(got.count == want.count, sourceLocation: sourceLocation)
        for (g, w) in zip(got, want) {
            #expect(g.merchant == w.merchant, sourceLocation: sourceLocation)
            #expect(g.installmentAmount == w.amount, sourceLocation: sourceLocation)
            #expect(g.currentInstallment == w.current, sourceLocation: sourceLocation)
            #expect(g.totalInstallments == w.total, sourceLocation: sourceLocation)
            #expect(g.date == w.date, sourceLocation: sourceLocation)
        }
    }

    // MARK: - Tek satır: işaret, tutar ve tarih biçimleri

    struct LineCase: Sendable, CustomTestStringConvertible {
        let line: String
        let expected: Expected
        var testDescription: String { line }
    }

    static let lineCases: [LineCase] = [
        // İşaret biçimleri
        LineCase(line: "12.10.2026 ORNEK MARKET 3/6 1.234,56 TL",
                 expected: Expected(merchant: "ORNEK MARKET", amount: dec("1234.56"), current: 3, total: 6, date: day(12, 10, 2026))),
        LineCase(line: "12.10.2026 ORNEK SPOR 3. Taksit / 6 750,00 TL",
                 expected: Expected(merchant: "ORNEK SPOR", amount: dec("750.00"), current: 3, total: 6, date: day(12, 10, 2026))),
        LineCase(line: "12.10.2026 ORNEK GIYIM Taksit 3/6 99,90",
                 expected: Expected(merchant: "ORNEK GIYIM", amount: dec("99.90"), current: 3, total: 6, date: day(12, 10, 2026))),
        LineCase(line: "12.10.2026 ORNEK KITAP (3/6) 45,00",
                 expected: Expected(merchant: "ORNEK KITAP", amount: dec("45.00"), current: 3, total: 6, date: day(12, 10, 2026))),
        LineCase(line: "ORNEK KITAP Taksit: 2/9 45,00",
                 expected: Expected(merchant: "ORNEK KITAP", amount: dec("45.00"), current: 2, total: 9, date: nil)),
        LineCase(line: "ORNEK KITAP TAKSIT 12/12 45,00",
                 expected: Expected(merchant: "ORNEK KITAP", amount: dec("45.00"), current: 12, total: 12, date: nil)),
        LineCase(line: "ORNEK KITAP 1/36 45,00",
                 expected: Expected(merchant: "ORNEK KITAP", amount: dec("45.00"), current: 1, total: 36, date: nil)),
        // Tutar biçimleri
        LineCase(line: "ORNEK AYAKKABI 2/3 1.234,56",
                 expected: Expected(merchant: "ORNEK AYAKKABI", amount: dec("1234.56"), current: 2, total: 3, date: nil)),
        LineCase(line: "ORNEK AYAKKABI 2/3 ₺1.234,56",
                 expected: Expected(merchant: "ORNEK AYAKKABI", amount: dec("1234.56"), current: 2, total: 3, date: nil)),
        LineCase(line: "ORNEK AYAKKABI 2/3 234,56 TL",
                 expected: Expected(merchant: "ORNEK AYAKKABI", amount: dec("234.56"), current: 2, total: 3, date: nil)),
        LineCase(line: "ORNEK AYAKKABI 2/3 1.234.567,89",
                 expected: Expected(merchant: "ORNEK AYAKKABI", amount: dec("1234567.89"), current: 2, total: 3, date: nil)),
        LineCase(line: "ORNEK AYAKKABI 2/3 0,99",
                 expected: Expected(merchant: "ORNEK AYAKKABI", amount: dec("0.99"), current: 2, total: 3, date: nil)),
        // Tarih biçimleri
        LineCase(line: "12/10/2026 ORNEK MOBILYA 4/10 500,00",
                 expected: Expected(merchant: "ORNEK MOBILYA", amount: dec("500.00"), current: 4, total: 10, date: day(12, 10, 2026))),
        LineCase(line: "29.02.2028 ORNEK MOBILYA 4/10 500,00",
                 expected: Expected(merchant: "ORNEK MOBILYA", amount: dec("500.00"), current: 4, total: 10, date: day(29, 2, 2028))),
        // Birden çok tutar: son sütun taksit tutarı
        LineCase(line: "12.10.2026 ORNEK TEKNO 3/6 6.000,00 1.000,00",
                 expected: Expected(merchant: "ORNEK TEKNO", amount: dec("1000.00"), current: 3, total: 6, date: day(12, 10, 2026))),
        // Faizsiz taksit gerçek taksit satırıdır
        LineCase(line: "ORNEK TEKNO Faizsiz Taksit 2/3 450,00",
                 expected: Expected(merchant: "ORNEK TEKNO", amount: dec("450.00"), current: 2, total: 3, date: nil)),
        // Türkçe harfli firma adı
        LineCase(line: "ÖRNEK ÇİÇEKÇİ ŞUBE 1/2 80,00",
                 expected: Expected(merchant: "ÖRNEK ÇİÇEKÇİ ŞUBE", amount: dec("80.00"), current: 1, total: 2, date: nil)),
    ]

    @Test("Parses a single installment line in every marker, amount and date format", arguments: lineCases)
    func singleLine(_ c: LineCase) {
        check(StatementParser.parse(lines: [c.line]), [c.expected])
    }

    // MARK: - OCR gürültüsü

    @Test("Reads letter O as zero inside amounts")
    func ocrLetterO() {
        let got = StatementParser.parse(lines: ["ORNEK GIYIM Taksit 2/4 1.2O0,5O"])
        check(got, [Expected(merchant: "ORNEK GIYIM", amount: Self.dec("1200.50"), current: 2, total: 4, date: nil)])
    }

    @Test("Tolerates extra spaces, tabs and padding")
    func extraSpaces() {
        let got = StatementParser.parse(lines: ["   12.10.2026 \t  ORNEK    MARKET     3 / 6    1.234,56   TL  "])
        check(got, [Expected(merchant: "ORNEK MARKET", amount: Self.dec("1234.56"), current: 3, total: 6, date: Self.day(12, 10, 2026))])
    }

    @Test("Takes the amount from the next line when the line is broken")
    func brokenLine() {
        let got = StatementParser.parse(lines: ["ORNEK MOBILYA 3. taksit / 12", "₺2.500,00", "ORNEK CAFE 1/2 10,00"])
        check(got, [
            Expected(merchant: "ORNEK MOBILYA", amount: Self.dec("2500.00"), current: 3, total: 12, date: nil),
            Expected(merchant: "ORNEK CAFE", amount: Self.dec("10.00"), current: 1, total: 2, date: nil),
        ])
    }

    @Test("Does not use a next line that holds more than an amount")
    func brokenLineNextNotAmountOnly() {
        #expect(StatementParser.parse(lines: ["ORNEK MOBILYA 3/12", "ORNEK CAFE 85,50"]).isEmpty)
    }

    @Test("A consumed amount line is not read again and a trailing marker line yields nothing")
    func brokenLineAtEnd() {
        #expect(StatementParser.parse(lines: ["ORNEK MOBILYA 3/12"]).isEmpty)
        #expect(StatementParser.parse(lines: ["ORNEK MOBILYA 3/12", ""]).isEmpty)
    }

    // MARK: - Üç farklı ekstre düzeni

    @Test("Layout 1: table-like columns with header, totals and a minimum payment")
    func tableLayout() {
        let lines = [
            "ORNEK KART EKSTRESI",
            "Hesap Kesim Tarihi 15.10.2026",
            "Son Ödeme Tarihi 25.10.2026",
            "TARIH      ACIKLAMA              TAKSIT   TUTAR       TAKSIT TUTARI",
            "03.10.2026 ORNEK MARKET           3/6      3.000,00    500,00",
            "04.10.2026 ORNEK CAFE                      85,50",
            "06.10.2026 ORNEK ELEKTRONIK       1/12     24.000,00   2.000,00",
            "08.10.2026 ORNEK IADE                      -250,00",
            "Toplam Harcama                             27.335,50",
            "Faiz Tutarı                                12,40",
            "KKDF                                       3,10",
            "Asgari Ödeme Tutarı                        4.000,00",
        ]
        check(StatementParser.parse(lines: lines), [
            Expected(merchant: "ORNEK MARKET", amount: Self.dec("500.00"), current: 3, total: 6, date: Self.day(3, 10, 2026)),
            Expected(merchant: "ORNEK ELEKTRONIK", amount: Self.dec("2000.00"), current: 1, total: 12, date: Self.day(6, 10, 2026)),
        ])
    }

    @Test("Layout 2: one line per transaction with the marker in parentheses")
    func parenthesesLayout() {
        let lines = [
            "05/10/2026 Ornek Kitabevi (2/3) ₺150,00",
            "06/10/2026 Ornek Benzin 640,25 TL",
            "07/10/2026 Ornek Mobilya (10/12) ₺1.234,56",
            "Ödenecek Tutar ₺2.024,81",
            "Gecikme Faizi 1/2 ₺5,00",
        ]
        check(StatementParser.parse(lines: lines), [
            Expected(merchant: "Ornek Kitabevi", amount: Self.dec("150.00"), current: 2, total: 3, date: Self.day(5, 10, 2026)),
            Expected(merchant: "Ornek Mobilya", amount: Self.dec("1234.56"), current: 10, total: 12, date: Self.day(7, 10, 2026)),
        ])
    }

    @Test("Layout 3: noisy OCR with extra spaces, O for 0 and amounts on the next line")
    func noisyOCRLayout() {
        let lines = [
            "  EKSTRE   OZETI  ",
            "12.10.2026  ORNEK   GIYIM   Taksit  2/4   1.2O0,5O  ",
            "13.10.2026 ORNEK MOBILYA   3. Taksit / 12",
            "   ₺2.5OO,OO",
            "14.10.2026   ORNEK   CAFE    85,5O",
            "15.10.2026 ORNEK SPOR (4/6)",
            "750,00 TL",
            "TOPLAM    4.521,00",
            "ASGARI ODEME  1.000,00",
        ]
        let got = StatementParser.parse(lines: lines)
        #expect(got.count == 3)
        #expect(got[0].merchant == "ORNEK GIYIM")
        #expect(got[0].installmentAmount == Self.dec("1200.50"))
        #expect(got[0].currentInstallment == 2 && got[0].totalInstallments == 4)
        #expect(got[1].merchant == "ORNEK MOBILYA")
        #expect(got[1].installmentAmount == Self.dec("2500.00"))
        #expect(got[1].currentInstallment == 3 && got[1].totalInstallments == 12)
        #expect(got[1].date == Self.day(13, 10, 2026))
        #expect(got[2].merchant == "ORNEK SPOR")
        #expect(got[2].installmentAmount == Self.dec("750.00"))
        #expect(got[2].currentInstallment == 4 && got[2].totalInstallments == 6)
        #expect(got[2].date == Self.day(15, 10, 2026))
    }

    // MARK: - Yok sayılan satırlar

    static let ignoredLines: [String] = [
        // Tek çekim
        "12.10.2026 ORNEK CAFE 85,50 TL",
        "ORNEK CAFE ₺1.234,56",
        // Toplam
        "Toplam Borç 5.000,00",
        "TOPLAM HARCAMA 1/2 5.000,00",
        "Dönem Borcu 1/2 2.000,00 TL",
        "Önceki Bakiye 1/2 100,00",
        // Faiz ve ücret
        "Faiz Tutarı 3/6 12,00",
        "Akdi Faiz 1/2 12,00",
        "Kart Ücreti 1/2 50,00",
        "Ücret 1/2 50,00",
        "KKDF 1/2 4,00",
        "BSMV 1/2 4,00",
        "Gecikme Faizi 1/2 7,00",
        // Asgari ödeme ve özet
        "Asgari Ödeme Tutarı 1/2 500,00 TL",
        "ASGARI ODEME 500,00",
        "Son Ödeme Tarihi 25/10/2026 1/2 500,00",
        "Hesap Kesim Tarihi 15.10.2026 1/2 500,00",
        "Ödenecek Tutar 1/2 ₺500,00",
        "Ekstre Borcu 1/2 500,00",
        // Çekimli özet ve ücret satırları
        "Dönem Borcu 1/2 2.000,00",
        "Toplam Borcunuz 1/2 2.000,00",
        "Kart Ücreti 1/2 50,00 TL",
        "Hesap Bakiyesi 1/2 100,00",
    ]

    @Test("Ignores totals, interest, fees, minimum payment and single purchases", arguments: ignoredLines)
    func ignoredLine(_ line: String) {
        #expect(StatementParser.parse(lines: [line]).isEmpty)
    }

    // MARK: - Tahmin yok

    static let neverGuessLines: [String] = [
        "ORNEK MARKET 3/6",                       // tutar yok
        "ORNEK MARKET 500,00",                    // işaret yok
        "ORNEK MARKET 7/6 500,00",                // şimdiki > toplam
        "ORNEK MARKET 0/6 500,00",                // sıfırıncı taksit
        "ORNEK MARKET 1/1 500,00",                // tek taksit taksit değil
        "ORNEK MARKET 1/0 500,00",
        "ORNEK MARKET 3/40 500,00",               // 36'dan fazla desteklenmez
        "ORNEK MARKET 3/6 -250,00",               // iade / eksi tutar
        "ORNEK MARKET 3/6 0,00",                  // sıfır tutar
        "ORNEK MARKET 3/6 100,5",                 // tek ondalık
        "ORNEK MARKET 3/6 1234.56",               // Türk biçimi değil
        "ORNEK MARKET 3/6 500",                   // ondalıksız
        "3/6 500,00",                             // firma adı yok
        "12.10.2026 3/6 500,00 TL",               // yalnızca tarih ve işaret
        "ORNEK MARKET 2/6 3/6 500,00",            // iki farklı işaret: belirsiz
        "12/10/2026 ORNEK CAFE 85,50",            // tarih işaret sanılmamalı
        "12.10.2026 ORNEK CAFE 85,50",
        "",
        "   ",
    ]

    @Test("Never guesses: unclear or invalid lines are not candidates", arguments: neverGuessLines)
    func neverGuess(_ line: String) {
        #expect(StatementParser.parse(lines: [line]).isEmpty)
    }

    @Test("Empty input gives no candidates")
    func emptyInput() {
        #expect(StatementParser.parse(lines: []).isEmpty)
    }

    @Test("An impossible date leaves the date empty but keeps the installment")
    func impossibleDate() {
        let got = StatementParser.parse(lines: ["31.04.2026 ORNEK MARKET 3/6 500,00"])
        #expect(got.count == 1)
        #expect(got.first?.date == nil)
        #expect(got.first?.installmentAmount == Self.dec("500.00"))
    }

    @Test("Keeps the order of lines and gives each candidate its own id")
    func orderAndIds() {
        let got = StatementParser.parse(lines: ["B MARKET 1/2 10,00", "A MARKET 2/3 20,00", "C MARKET 3/4 30,00"])
        #expect(got.map(\.merchant) == ["B MARKET", "A MARKET", "C MARKET"])
        #expect(Set(got.map(\.id)).count == 3)
    }

    @Test("Parsing the same text twice gives the same fields")
    func deterministic() {
        let lines = ["12.10.2026 ORNEK MARKET 3/6 1.234,56 TL"]
        let a = StatementParser.parse(lines: lines)
        let b = StatementParser.parse(lines: lines)
        #expect(a.map(\.merchant) == b.map(\.merchant))
        #expect(a.map(\.installmentAmount) == b.map(\.installmentAmount))
        #expect(a.map(\.currentInstallment) == b.map(\.currentInstallment))
        #expect(a.map(\.totalInstallments) == b.map(\.totalInstallments))
        #expect(a.map(\.date) == b.map(\.date))
    }

    // MARK: - Atlama anahtar kelimesiyle başlayan firma adları

    static let keywordPrefixedMerchants: [LineCase] = [
        LineCase(line: "BORCELIK 2/3 150,00",
                 expected: Expected(merchant: "BORCELIK", amount: dec("150.00"), current: 2, total: 3, date: nil)),
        LineCase(line: "DONEMSEL 1/2 80,00",
                 expected: Expected(merchant: "DONEMSEL", amount: dec("80.00"), current: 1, total: 2, date: nil)),
        LineCase(line: "UCRETSIZ KARGO 3/6 99,90",
                 expected: Expected(merchant: "UCRETSIZ KARGO", amount: dec("99.90"), current: 3, total: 6, date: nil)),
        LineCase(line: "EKSTRELI 4/9 200,00 TL",
                 expected: Expected(merchant: "EKSTRELI", amount: dec("200.00"), current: 4, total: 9, date: nil)),
    ]

    @Test("Merchant names that merely start with a skip keyword stay candidates", arguments: keywordPrefixedMerchants)
    func keywordPrefixedMerchant(_ c: LineCase) {
        check(StatementParser.parse(lines: [c.line]), [c.expected])
    }

    // MARK: - İki haneli yıl

    @Test("A two-digit-year date is not read as a marker and leaves the date empty")
    func twoDigitYearDate() {
        let got = StatementParser.parse(lines: ["12.10.26 ORNEK MARKET 3/6 500,00"])
        check(got, [Expected(merchant: "ORNEK MARKET", amount: Self.dec("500.00"), current: 3, total: 6, date: nil)])
    }
}
