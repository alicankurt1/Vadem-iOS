import CoreGraphics
import Foundation

/// A piece of text recognized by OCR and where it sits on the page.
///
/// `boundingBox` is in normalized coordinates (`0...1`) with the origin at the **bottom left**, as Vision reports it.
public struct RecognizedTextBox: Sendable, Hashable {
    /// The recognized text.
    public var text: String
    /// The text's box in normalized, bottom-left-origin coordinates.
    public var boundingBox: CGRect

    /// Creates a box for `text` at `boundingBox`.
    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

/// Puts OCR boxes back into reading order: rows top to bottom, boxes left to right inside a row.
///
/// Statements are tables; OCR often returns a row's columns (merchant, `3/6`, amount) as separate boxes.
/// Boxes whose vertical centers are closer than half the row's height are one row, joined with a space,
/// so ``VademCore/StatementParser`` sees the whole row as one line.
public enum StatementLineAssembler {
    /// The lines of `boxes` in reading order; empty texts are dropped.
    public static func lines(from boxes: [RecognizedTextBox]) -> [String] {
        let boxes = boxes
            .map { RecognizedTextBox(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), boundingBox: $0.boundingBox) }
            .filter { !$0.text.isEmpty }
            // Üstten alta: Vision'da y yukarı doğru artar.
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        var rows: [[RecognizedTextBox]] = []
        for box in boxes {
            // Satırın ilk kutusu referanstır; merkezler yarım satır yüksekliğinden yakınsa aynı satır.
            if let first = rows.last?.first,
               abs(first.boundingBox.midY - box.boundingBox.midY) < max(first.boundingBox.height, box.boundingBox.height) / 2 {
                rows[rows.count - 1].append(box)
            } else {
                rows.append([box])
            }
        }
        return rows.map { row in
            row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }.map(\.text).joined(separator: " ")
        }
    }
}
