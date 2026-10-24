import Foundation

/// Kullanıcının yazdığı metnin (kalem başlığı, kart adı) modele güvenle verilebilen hali.
///
/// Kontrol karakterleri, satır sonları ve görünmez biçim karakterleri (ör. çift yönlü
/// metin geçersiz kılmaları) boşluğa çevrilir, ardışık boşluklar tek boşluğa indirilir,
/// baştaki/sondaki boşluk atılır ve sonuç ``maxLength`` karakterle sınırlanır. Böylece bir
/// başlık ek satır açarak talimat gibi görünemez ve çıktı biçimini bozamaz.
/// Temizlik sonrası boş kalan metin yerine ``fallback`` kullanılır.
public struct PromptSafeText: Sendable, Hashable, Codable {
    /// The most characters a cleaned text has.
    public static let maxLength = 40
    /// Used when nothing is left after cleaning.
    public static let fallback = "(untitled)"

    /// The cleaned text: single line, trimmed, at most ``maxLength`` characters, never empty.
    public let value: String

    /// Cleans `raw`: control characters, newlines and format characters become spaces,
    /// whitespace runs collapse, the result is trimmed and cut to ``maxLength`` characters.
    public init(_ raw: String) {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            // ZWJ/ZWNJ (U+200D/U+200C) kalır: Türkçe dışı yazılarda ve emoji dizilerinde anlam taşır.
            // Çift yönlü kontroller, sıfır genişlikli boşluk ve diğer biçim karakterleri boşluğa döner.
            if scalar.value == 0x200C || scalar.value == 0x200D {
                scalars.append(scalar)
                continue
            }
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator:
                scalars.append(" ")
            default:
                scalars.append(scalar)
            }
        }
        // Kalan boşluk türleri (tab zaten yukarıda gitti; NBSP gibi olanlar) tek boşluğa iner.
        let words = String(scalars).split(whereSeparator: { $0.isWhitespace })
        let joined = words.joined(separator: " ")
        // Kesme Character sınırında yapılır; birleşik karakterler ortadan bölünmez.
        let cut = String(joined.prefix(PromptSafeText.maxLength))
            .trimmingCharacters(in: .whitespaces)
        self.value = cut.isEmpty ? PromptSafeText.fallback : cut
    }

    /// Decodes a string and cleans it like ``init(_:)``.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(String.self))
    }

    /// Encodes ``value`` as a plain string.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
