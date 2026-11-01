import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Vision
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Reads statement text on the device; nothing is uploaded.
///
/// - PDF: each page's text layer via PDFKit; a page without text (a scan) is rendered and read with OCR.
/// - Image: OCR with Vision's `VNRecognizeTextRequest` (accurate, `tr-TR` and `en-US`).
///
/// OCR boxes are put in reading order by ``StatementLineAssembler``.
public struct OnDeviceStatementTextSource: StatementTextSource {
    /// The OCR languages, in order of preference; unsupported ones are left out on the device.
    public static let recognitionLanguages = ["tr-TR", "en-US"]

    /// Creates the source.
    public init() {}

    public func lines(from input: StatementInput) async throws -> [String] {
        // Vision ve PDFKit eşzamanlı ve yavaş: ana aktörün dışında, ayrı bir görevde çalışır.
        let lines = try await Task.detached(priority: .userInitiated) {
            switch input {
            case .pdf(let data): try Self.pdfLines(data)
            case .image(let data): try Self.imageLines(data)
            }
        }.value
        guard !lines.isEmpty else { throw StatementTextSourceError.nothingReadable }
        return lines
    }

    // MARK: - PDF

    private static func pdfLines(_ data: Data) throws -> [String] {
        guard let document = PDFDocument(data: data), !document.isLocked else {
            throw StatementTextSourceError.unreadableFile
        }
        var lines: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let pageLines = textLines(page.string ?? "")
            if !pageLines.isEmpty {
                lines += pageLines
            } else if let image = render(page) {
                // Metin katmanı yok (taranmış sayfa): sayfa resme çevrilip OCR'dan geçer.
                lines += try recognizeLines(in: image, orientation: .up)
            }
        }
        return lines
    }

    // Metni satırlara böler; boş satırlar atılır.
    private static func textLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // Sayfayı OCR için yeterli çözünürlükte (uzun kenar en çok 3000 px) beyaz zeminli resme çevirir.
    private static func render(_ page: PDFPage) -> CGImage? {
        var size = page.bounds(for: .mediaBox).size
        // Döndürülmüş sayfada genişlik ve yükseklik yer değiştirir.
        if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(3, 3000 / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let thumbnail = page.thumbnail(of: target, for: .mediaBox)
        #if canImport(UIKit)
        return thumbnail.cgImage
        #elseif canImport(AppKit)
        return thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return nil
        #endif
    }

    // MARK: - Resim

    private static func imageLines(_ data: Data) throws -> [String] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw StatementTextSourceError.unreadableFile
        }
        // Fotoğrafın EXIF yönü OCR'a verilir; yan çekilmiş ekstre de doğru okunur.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
        return try recognizeLines(in: image, orientation: orientation)
    }

    // MARK: - OCR (PDF ve resim ortak)

    private static func recognizeLines(in image: CGImage, orientation: CGImagePropertyOrientation) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Cihazın desteklemediği dil istenirse Vision hata verir; yalnızca desteklenenler istenir.
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let languages = recognitionLanguages.filter { language in
            supported.contains { $0.caseInsensitiveCompare(language) == .orderedSame }
        }
        if !languages.isEmpty { request.recognitionLanguages = languages }
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        try handler.perform([request])
        let boxes = (request.results ?? []).compactMap { observation -> RecognizedTextBox? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return RecognizedTextBox(text: text, boundingBox: observation.boundingBox)
        }
        return StatementLineAssembler.lines(from: boxes)
    }
}
