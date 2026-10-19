import Foundation

// İki öğe tipi aynı başlık kuralını paylaşır; kural tek yerde tutulur.
enum ItemTitle {
    // Kırpılmış başlığı döner; boşsa veya `maxLength`'i aşıyorsa `nil`.
    static func validated(_ title: String, maxLength: Int) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return nil }
        return trimmed
    }
}
