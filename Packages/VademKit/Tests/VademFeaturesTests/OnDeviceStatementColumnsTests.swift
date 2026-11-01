import Foundation
import Testing
import VademCore

@testable import VademFeatures

// Çok sütunlu uydurma ekstre (#256): tarih, firma, "AxN=T k.Taksit", bonus ve tutar ayrı sütunlarda.
// Gerçek PDFKit/Vision kullanılır; OCR çıktısı OS sürümüne göre değişebilir, bu yüzden ayrıştırılan alanlar denetlenir.
@Suite("OnDeviceStatementTextSource: multi-column statement")
struct OnDeviceStatementColumnsTests {
    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: ext))
        return try Data(contentsOf: url)
    }

    private func dec(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

    @Test("PDF columns yield the three installments, the statement total and the due date")
    func pdfColumns() async throws {
        let lines = try await OnDeviceStatementTextSource().lines(from: .pdf(fixture("statement-columns", "pdf")))
        let result = StatementParser.parseStatement(lines: lines)
        #expect(result.candidates.count == 3, "lines: \(lines)")
        #expect(result.candidates.map(\.totalInstallments) == [9, 3, 2])
        #expect(result.candidates.map(\.currentInstallment) == [1, 1, 2])
        #expect(result.candidates.map(\.installmentAmount) == [dec("1878.96"), dec("254.31"), dec("1194.50")])
        #expect(result.candidates.map(\.merchant) == ["EXAMPLE SIGORTA", "EXAMPLE SHOP", "EXAMPLE MARKET"])
        #expect(result.candidates.map(\.date) == [
            StatementDate(year: 2026, month: 10, day: 16), StatementDate(year: 2026, month: 10, day: 18),
            StatementDate(year: 2026, month: 9, day: 30),
        ])
        let summary = try #require(result.summary, "lines: \(lines)")
        #expect(summary.total == dec("46354.97"))
        #expect(summary.dueDate == StatementDate(year: 2026, month: 11, day: 2))
    }

    @Test("Header text is never a merchant")
    func pdfHeaderNotMerchant() async throws {
        let lines = try await OnDeviceStatementTextSource().lines(from: .pdf(fixture("statement-columns", "pdf")))
        let merchants = StatementParser.parse(lines: lines).map(\.merchant)
        #expect(merchants.allSatisfy { !$0.localizedCaseInsensitiveContains("HARCAMALARINIZ") && !$0.localizedCaseInsensitiveContains("Bonus") })
    }

    @Test("Image of the same layout goes through OCR into installments and a summary")
    func imageColumns() async throws {
        let lines = try await OnDeviceStatementTextSource().lines(from: .image(fixture("statement-columns", "png")))
        let result = StatementParser.parseStatement(lines: lines)
        // OCR küçük sapmalar yapabilir: sayılar ve sıra aranır, birebir metin değil.
        #expect(result.candidates.count == 3, "lines: \(lines)")
        #expect(result.candidates.map(\.totalInstallments) == [9, 3, 2])
        #expect(result.candidates.map(\.currentInstallment) == [1, 1, 2])
        #expect(result.candidates.map(\.installmentAmount) == [dec("1878.96"), dec("254.31"), dec("1194.50")])
        let summary = try #require(result.summary, "lines: \(lines)")
        #expect(summary.total == dec("46354.97"))
        #expect(summary.dueDate == StatementDate(year: 2026, month: 11, day: 2))
    }
}
