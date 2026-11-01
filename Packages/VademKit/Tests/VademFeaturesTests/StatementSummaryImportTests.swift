import Foundation
import Testing
import VademCore

@testable import VademFeatures

// Ekstre özeti ile içe aktarma durumu (#256); uydurma satırlar, dosya okunmaz.
@MainActor
@Suite("StatementImportViewModel: statement summary")
struct StatementSummaryImportTests {
    private static let summaryLines = ["Dönem Borcunuz 46.354,97 TL", "Son Ödeme Tarihi 02 Kasım 2026"]
    private static let installmentLine = "16 Ekim 2026 EXAMPLE SHOP 254,31x3=762,89 1.Taksit 0,15 254,31"

    @Test("A statement with only a summary still reaches found, with no candidates")
    func summaryOnly() {
        let model = StatementImportViewModel(source: ScriptedStatementTextSource(lines: []))
        model.show(lines: Self.summaryLines)
        guard case .found(let candidates, let summary) = model.state else {
            Issue.record("expected found, got \(model.state)")
            return
        }
        #expect(candidates.isEmpty)
        #expect(summary?.total == Decimal(string: "46354.97", locale: Locale(identifier: "en_US_POSIX")))
        #expect(summary?.dueDate == StatementDate(year: 2026, month: 11, day: 2))
    }

    @Test("Installments and a summary are both in found")
    func both() {
        let model = StatementImportViewModel(source: ScriptedStatementTextSource(lines: []))
        model.show(lines: [Self.installmentLine] + Self.summaryLines)
        guard case .found(let candidates, let summary) = model.state else {
            Issue.record("expected found, got \(model.state)")
            return
        }
        #expect(candidates.count == 1)
        #expect(candidates.first?.totalInstallments == 3)
        #expect(summary != nil)
    }

    @Test("Installments without a summary are found with a nil summary")
    func candidatesOnly() {
        let model = StatementImportViewModel(source: ScriptedStatementTextSource(lines: []))
        model.show(lines: [Self.installmentLine, "Dönem Borcunuz 100,00 TL"])
        guard case .found(let candidates, let summary) = model.state else {
            Issue.record("expected found, got \(model.state)")
            return
        }
        #expect(candidates.count == 1)
        #expect(summary == nil)
    }

    @Test("Neither installments nor a summary is noInstallments; blank lines are noText")
    func neither() {
        let model = StatementImportViewModel(source: ScriptedStatementTextSource(lines: []))
        model.show(lines: ["Merhaba", "Dönem Borcunuz 100,00 TL"])
        #expect(model.state == .noInstallments)
        model.show(lines: ["  ", ""])
        #expect(model.state == .noText)
    }

    @Test("A summary-only read through the source ends in found")
    func throughSource() async {
        let model = StatementImportViewModel(source: ScriptedStatementTextSource(lines: Self.summaryLines))
        await model.read(.pdf(Data()))
        if case .found(let candidates, let summary) = model.state {
            #expect(candidates.isEmpty)
            #expect(summary != nil)
        } else {
            Issue.record("expected found, got \(model.state)")
        }
    }
}
