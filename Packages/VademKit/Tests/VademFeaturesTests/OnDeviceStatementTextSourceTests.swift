import Foundation
import Testing
import VademCore

@testable import VademFeatures

// Gerçek PDFKit/Vision ile uydurma ekstre dosyaları; OCR çıktısı OS sürümüne göre değişebilir,
// bu yüzden birebir metin yerine içerme ve ayrıştırılan adaylar denetlenir.
@Suite("OnDeviceStatementTextSource")
struct OnDeviceStatementTextSourceTests {
    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: ext))
        return try Data(contentsOf: url)
    }

    @Test("PDF text layer yields the installment lines and parses into candidates")
    func pdfTextLayer() async throws {
        let data = try fixture("statement-sample", "pdf")
        let lines = try await OnDeviceStatementTextSource().lines(from: .pdf(data))
        let joined = lines.joined(separator: "\n")
        #expect(joined.contains("ORNEK ELEKTRONIK"))
        #expect(joined.contains("3/6"))

        let candidates = StatementParser.parse(lines: lines)
        #expect(candidates.count == 2)
        let first = try #require(candidates.first)
        #expect(first.currentInstallment == 3)
        #expect(first.totalInstallments == 6)
        #expect(first.installmentAmount == Decimal(string: "1234.56"))
        #expect(first.merchant.contains("ELEKTRONIK"))
        #expect(candidates.last?.installmentAmount == 450)
    }

    @Test("Image goes through OCR and the installment lines come out in order")
    func imageOCR() async throws {
        let data = try fixture("statement-sample", "png")
        let lines = try await OnDeviceStatementTextSource().lines(from: .image(data))
        #expect(!lines.isEmpty)
        let candidates = StatementParser.parse(lines: lines)
        // OCR küçük sapmalar yapabilir: iki taksit satırı ve sırası aranır.
        #expect(candidates.count == 2)
        #expect(candidates.map(\.totalInstallments) == [6, 4])
        #expect(candidates.map(\.currentInstallment) == [3, 2])
    }

    @Test("Garbage bytes are unreadable files", arguments: [
        StatementInput.pdf(Data("not a pdf".utf8)),
        StatementInput.image(Data("not an image".utf8)),
    ])
    func garbage(input: StatementInput) async {
        await #expect(throws: StatementTextSourceError.unreadableFile) {
            _ = try await OnDeviceStatementTextSource().lines(from: input)
        }
    }

    @Test("Empty data is unreadable")
    func emptyData() async {
        await #expect(throws: StatementTextSourceError.self) {
            _ = try await OnDeviceStatementTextSource().lines(from: .pdf(Data()))
        }
    }

    @Test("OCR languages are Turkish and English")
    func languages() {
        #expect(OnDeviceStatementTextSource.recognitionLanguages == ["tr-TR", "en-US"])
    }
}
