import Foundation
import Testing

@testable import VademCore

// Anonim, uydurma ekstre satırları (#256): "AxN=T k.Taksit" işareti, ay adlı tarihler, ekstre özeti.
@Suite("StatementParser: AxN=T k.Taksit, month-name dates, statement summary")
struct StatementInstallmentTotalParserTests {
    private static func dec(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }
    private static func date(_ d: Int, _ m: Int, _ y: Int) -> StatementDate { StatementDate(year: y, month: m, day: d)! }

    // MARK: - Sorunda yazılan satırlar, basıldığı gibi

    @Test("Issue lines are read exactly as printed")
    func issueLines() throws {
        let lines = [
            "16 Ekim 2026 EXAMPLE SIGORTA 1.878,96x9=16.910,00 1.Taksit 8,46 1.878,96",
            "18 Ekim 2026 EXAMPLE SHOP 254,31x3=762,89 1.Taksit 0,15 254,31",
            "30 Eylül 2026 EXAMPLE MARKET 1.194,50x2=2.389,00 2.Taksit 1.194,50",
        ]
        let got = StatementParser.parse(lines: lines)
        #expect(got.count == 3)
        #expect(got.map(\.merchant) == ["EXAMPLE SIGORTA", "EXAMPLE SHOP", "EXAMPLE MARKET"])
        #expect(got.map(\.installmentAmount) == [Self.dec("1878.96"), Self.dec("254.31"), Self.dec("1194.50")])
        #expect(got.map(\.currentInstallment) == [1, 1, 2])
        #expect(got.map(\.totalInstallments) == [9, 3, 2])
        #expect(got.map(\.date) == [Self.date(16, 10, 2026), Self.date(18, 10, 2026), Self.date(30, 9, 2026)])
    }

    // MARK: - İşaret yazımları

    @Test("Marker spellings: case, TAKSİT, with or without a space", arguments: [
        "12.10.2026 EXAMPLE SHOP 500,00x4=2.000,00 2.Taksit",
        "12.10.2026 EXAMPLE SHOP 500,00x4=2.000,00 2.taksit",
        "12.10.2026 EXAMPLE SHOP 500,00x4=2.000,00 2.TAKSİT",
        "12.10.2026 EXAMPLE SHOP 500,00x4=2.000,00 2.TAKSIT",
        "12.10.2026 EXAMPLE SHOP 500,00x4=2.000,00 2. Taksit",
        "12.10.2026 EXAMPLE SHOP 500,00X4=2.000,00 2.Taksit",
        "12.10.2026 EXAMPLE SHOP 500,00x4=2.000,00 2.Taksit 3,10",
    ])
    func spellings(line: String) throws {
        let got = StatementParser.parse(lines: [line])
        let candidate = try #require(got.first)
        #expect(got.count == 1)
        #expect(candidate.currentInstallment == 2)
        #expect(candidate.totalInstallments == 4)
        #expect(candidate.installmentAmount == 500)
        #expect(candidate.merchant == "EXAMPLE SHOP")
    }

    @Test("Bonus column is not the amount, the monthly amount is")
    func bonusColumn() throws {
        let got = StatementParser.parse(lines: ["16 Ekim 2026 EXAMPLE SIGORTA 1.878,96x9=16.910,00 1.Taksit 8,46"])
        #expect(got.first?.installmentAmount == Self.dec("1878.96"))
    }

    // MARK: - Aritmetik toleransı: basılı toplamın %1'i

    struct ArithmeticCase: Sendable, CustomTestStringConvertible {
        let line: String
        let accepted: Bool
        var testDescription: String { line }
    }

    @Test("monthly x count must be within 1% of the printed total", arguments: [
        // Tam eşit.
        ArithmeticCase(line: "EXAMPLE SHOP 100,00x10=1.000,00 1.Taksit", accepted: true),
        // 254,31x3 = 762,93 ile 762,89: 4 kuruş fark.
        ArithmeticCase(line: "EXAMPLE SHOP 254,31x3=762,89 1.Taksit", accepted: true),
        // Tam %1 sınırı (fark 10,00 = 1000'in %1'i): dahil.
        ArithmeticCase(line: "EXAMPLE SHOP 101,00x10=1.000,00 1.Taksit", accepted: true),
        // Alt yönde de aynı.
        ArithmeticCase(line: "EXAMPLE SHOP 99,00x10=1.000,00 1.Taksit", accepted: true),
        // %1'in hemen üstü: 1.021,00 - 1.000,00 = 21 > 10.
        ArithmeticCase(line: "EXAMPLE SHOP 102,10x10=1.000,00 1.Taksit", accepted: false),
        ArithmeticCase(line: "EXAMPLE SHOP 98,00x10=1.000,00 1.Taksit", accepted: false),
        // Çok farklı toplam.
        ArithmeticCase(line: "EXAMPLE SHOP 100,00x10=2.000,00 1.Taksit", accepted: false),
        ArithmeticCase(line: "EXAMPLE SHOP 1.878,96x9=1.910,00 1.Taksit", accepted: false),
    ])
    func arithmetic(testCase: ArithmeticCase) {
        let got = StatementParser.parse(lines: [testCase.line])
        #expect(got.count == (testCase.accepted ? 1 : 0))
    }

    @Test("Invalid current or count in the x-form is skipped", arguments: [
        "EXAMPLE SHOP 100,00x4=400,00 5.Taksit",   // şimdiki > toplam
        "EXAMPLE SHOP 100,00x4=400,00 0.Taksit",   // şimdiki 0
        "EXAMPLE SHOP 400,00x1=400,00 1.Taksit",   // tek taksit
        "EXAMPLE SHOP 0,00x4=0,00 1.Taksit",       // sıfır tutar
    ])
    func invalidNumbers(line: String) {
        #expect(StatementParser.parse(lines: [line]).isEmpty)
    }

    // MARK: - Ay adlı tarihler

    struct MonthCase: Sendable, CustomTestStringConvertible {
        let text: String
        let month: Int
        var testDescription: String { "\(text) → \(month)" }
    }

    @Test("All twelve Turkish month names, any case, İ and ı aware", arguments: [
        MonthCase(text: "Ocak", month: 1), MonthCase(text: "OCAK", month: 1),
        MonthCase(text: "Şubat", month: 2), MonthCase(text: "ŞUBAT", month: 2), MonthCase(text: "subat", month: 2),
        MonthCase(text: "Mart", month: 3), MonthCase(text: "MART", month: 3),
        MonthCase(text: "Nisan", month: 4), MonthCase(text: "NİSAN", month: 4), MonthCase(text: "NISAN", month: 4),
        MonthCase(text: "Mayıs", month: 5), MonthCase(text: "MAYIS", month: 5), MonthCase(text: "mayis", month: 5),
        MonthCase(text: "Haziran", month: 6), MonthCase(text: "HAZİRAN", month: 6),
        MonthCase(text: "Temmuz", month: 7), MonthCase(text: "TEMMUZ", month: 7),
        MonthCase(text: "Ağustos", month: 8), MonthCase(text: "AĞUSTOS", month: 8), MonthCase(text: "agustos", month: 8),
        MonthCase(text: "Eylül", month: 9), MonthCase(text: "EYLÜL", month: 9),
        MonthCase(text: "Ekim", month: 10), MonthCase(text: "EKİM", month: 10),
        MonthCase(text: "Kasım", month: 11), MonthCase(text: "KASIM", month: 11),
        MonthCase(text: "Aralık", month: 12), MonthCase(text: "ARALIK", month: 12),
    ])
    func monthNames(testCase: MonthCase) throws {
        let got = StatementParser.parse(lines: ["14 \(testCase.text) 2026 EXAMPLE SHOP 3/6 100,00"])
        let candidate = try #require(got.first)
        #expect(candidate.date == StatementDate(year: 2026, month: testCase.month, day: 14))
        #expect(candidate.merchant == "EXAMPLE SHOP")
        #expect(candidate.currentInstallment == 3)
    }

    @Test("A month-name date is never read as a marker or an amount, and an invalid day gives no date")
    func monthNameEdgeCases() throws {
        let got = StatementParser.parse(lines: ["31 Nisan 2026 EXAMPLE SHOP 3/6 100,00"])
        // 31 Nisan yok: aday kalır, tarih nil olur (uydurulmaz).
        #expect(got.count == 1)
        #expect(got.first?.date == nil)
        let leap = StatementParser.parse(lines: ["29 Şubat 2028 EXAMPLE SHOP 3/6 100,00"])
        #expect(leap.first?.date == StatementDate(year: 2028, month: 2, day: 29))
    }

    // MARK: - Birleşmiş başlık

    @Test("A header joined to the row never becomes the merchant", arguments: [
        "HARCAMALARINIZ - Bonus kazanın! 16 Ekim 2026 EXAMPLE SIGORTA 1.878,96x9=16.910,00 1.Taksit 8,46 1.878,96",
        "HARCAMALARINIZ - Bonus kazanın! 16 Ekim 2026 EXAMPLE SIGORTA 3/9 1.878,96",
        "TOPLAM HARCAMALARINIZ 16 Ekim 2026 EXAMPLE SIGORTA 1.878,96x9=16.910,00 1.Taksit",
    ])
    func joinedHeader(line: String) throws {
        let got = StatementParser.parse(lines: [line])
        let candidate = try #require(got.first)
        #expect(got.count == 1)
        #expect(candidate.merchant == "EXAMPLE SIGORTA")
        #expect(candidate.date == Self.date(16, 10, 2026))
        #expect(candidate.installmentAmount == Self.dec("1878.96"))
    }

    // MARK: - Regresyon: eski işaretler yeni özellikle birlikte

    @Test("Old markers still work next to the x-form")
    func oldMarkersStillWork() {
        let got = StatementParser.parse(lines: [
            "12.10.2026 ORNEK ELEKTRONIK 3/6 1.234,56 TL",
            "16 Ekim 2026 EXAMPLE SHOP 254,31x3=762,89 1.Taksit 0,15 254,31",
            "15.10.2026 ORNEK GIYIM Taksit 2/4 450,00",
        ])
        #expect(got.map(\.merchant) == ["ORNEK ELEKTRONIK", "EXAMPLE SHOP", "ORNEK GIYIM"])
        #expect(got.map(\.totalInstallments) == [6, 3, 4])
    }

    // MARK: - Ekstre özeti

    private static let installmentLines = [
        "16 Ekim 2026 EXAMPLE SIGORTA 1.878,96x9=16.910,00 1.Taksit 8,46 1.878,96",
        "18 Ekim 2026 EXAMPLE SHOP 254,31x3=762,89 1.Taksit 0,15 254,31",
    ]

    @Test("Statement total and due date are found, separate from the candidates")
    func summaryBasic() throws {
        let lines = Self.installmentLines + [
            "Dönem Borcunuz 46.354,97 TL",
            "Asgari Ödeme Tutarı 9.270,99 TL",
            "Son Ödeme Tarihi 02 Kasım 2026",
        ]
        let result = StatementParser.parseStatement(lines: lines)
        let summary = try #require(result.summary)
        #expect(summary.total == Self.dec("46354.97"))
        #expect(summary.dueDate == Self.date(2, 11, 2026))
        // Özet satırları taksit adayı olmaz.
        #expect(result.candidates.count == 2)
        #expect(result.candidates.map(\.merchant) == ["EXAMPLE SIGORTA", "EXAMPLE SHOP"])
        // parse(lines:) aynı adayları verir.
        #expect(StatementParser.parse(lines: lines).map(\.merchant) == result.candidates.map(\.merchant))
    }

    @Test("Minimum payment on the same line or before the total is not taken as the total", arguments: [
        ["Dönem Borcunuz 46.354,97 TL Asgari Ödeme Tutarı 9.270,99 TL", "Son Ödeme Tarihi 02 Kasım 2026"],
        ["Asgari Ödeme Tutarı 9.270,99 TL", "Dönem Borcunuz 46.354,97 TL", "Son Ödeme Tarihi 02 Kasım 2026"],
        ["DÖNEM BORCUNUZ 46.354,97 TL", "ASGARİ ÖDEME 9.270,99", "SON ÖDEME TARİHİ 02 KASIM 2026"],
    ])
    func minimumNotTaken(lines: [String]) throws {
        let summary = try #require(StatementParser.parseStatement(lines: lines).summary)
        #expect(summary.total == Self.dec("46354.97"))
    }

    @Test("Toplam Borcunuz is used when there is no Dönem Borcunuz; Dönem wins when both exist")
    func totalLabelPriority() throws {
        let only = try #require(StatementParser.parseStatement(lines: [
            "Toplam Borcunuz 1.500,00 TL", "Son Ödeme Tarihi 05.11.2026",
        ]).summary)
        #expect(only.total == 1500)
        #expect(only.dueDate == Self.date(5, 11, 2026))
        let both = try #require(StatementParser.parseStatement(lines: [
            "Toplam Borcunuz 1.500,00 TL", "Dönem Borcunuz 900,00 TL", "Son Ödeme Tarihi 05.11.2026",
        ]).summary)
        #expect(both.total == 900)
    }

    @Test("Amount and date on the line after their label are read")
    func valuesOnNextLine() throws {
        let summary = try #require(StatementParser.parseStatement(lines: [
            "Dönem Borcunuz", "46.354,97 TL", "Son Ödeme Tarihi", "02 Kasım 2026",
        ]).summary)
        #expect(summary.total == Self.dec("46354.97"))
        #expect(summary.dueDate == Self.date(2, 11, 2026))
    }

    @Test("Without both a total and a due date there is no summary", arguments: [
        ["Dönem Borcunuz 46.354,97 TL"],
        ["Son Ödeme Tarihi 02 Kasım 2026"],
        ["Asgari Ödeme Tutarı 9.270,99 TL", "Son Ödeme Tarihi 02 Kasım 2026"],
        ["Dönem Borcunuz 0,00 TL", "Son Ödeme Tarihi 02 Kasım 2026"],
        ["Dönem Borcunuz 46.354,97 TL", "Son Ödeme Tarihi"],
        ["Dönem Borcunuz", "Son Ödeme Tarihi 02 Kasım 2026"],
        [],
    ])
    func noSummary(lines: [String]) {
        #expect(StatementParser.parseStatement(lines: lines).summary == nil)
    }

    @Test("A label line without a value does not stop the search; a later labelled line is used")
    func laterLabelledLine() throws {
        let totalCase = try #require(StatementParser.parseStatement(lines: [
            "Dönem Borcunuz ekstre kesim tarihindeki borcunuzu gösterir.",
            "Ödemelerinizi zamanında yapmanız önerilir.",
            "Dönem Borcunuz 46.354,97 TL",
            "Son Ödeme Tarihi 02 Kasım 2026",
        ]).summary)
        #expect(totalCase.total == Self.dec("46354.97"))

        let dueCase = try #require(StatementParser.parseStatement(lines: [
            "Dönem Borcunuz 46.354,97 TL",
            "Son Ödeme Tarihi için ödeme yapmayı unutmayınız.",
            "Teşekkür ederiz.",
            "Son Ödeme Tarihi 02 Kasım 2026",
        ]).summary)
        #expect(dueCase.dueDate == Self.date(2, 11, 2026))
        #expect(dueCase.total == Self.dec("46354.97"))
    }

    @Test("A statement with a summary but no installment line has no candidates")
    func summaryWithoutCandidates() throws {
        let result = StatementParser.parseStatement(lines: ["Dönem Borcunuz 100,00 TL", "Son Ödeme Tarihi 02 Kasım 2026"])
        #expect(result.candidates.isEmpty)
        #expect(result.summary != nil)
    }
}
