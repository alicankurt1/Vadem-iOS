import Foundation

/// Finds installment lines in the text of a credit card statement.
///
/// The input is plain text lines, as OCR or PDF text extraction returns them. The parser never
/// guesses: a line becomes an ``InstallmentCandidate`` only when it has a clear installment marker
/// and an amount. Rules:
/// - **Marker**: `3/6`, `3. taksit / 6`, `Taksit 3/6` or `(3/6)` (any case, Turkish `İ`/`ı` aware).
///   Valid only when `1 ≤ current ≤ total`, `total ≥ 2` and `total` is in ``InstallmentPlan/supportedCounts``.
///   Two different markers on one line make it ambiguous, so it is skipped.
/// - **Amount**: Turkish format with 2 fraction digits (`234,56`, `1.234,56`, `1.234,56 TL`, `₺1.234,56`).
///   When a line has several amounts, the **last** one is the installment amount (statements print the
///   purchase total first and the installment amount in the last column). A negative (credit) or zero
///   amount means no candidate. Inside amounts the letter `O` is read as `0` (OCR noise).
/// - **Date**: `12.10.2026` or `12/10/2026`; optional. Dates are never read as markers.
/// - **Merchant**: what is left after removing the date, marker, amounts, currency and noise words;
///   it must contain a letter.
/// - **Skipped lines**: totals, interest and fees (faiz, ücret, KKDF, BSMV, gecikme), minimum payment
///   and statement summary lines, even when they contain something like `1/2`.
/// - **Broken lines**: a line with a marker but no amount takes its amount from the next line when that
///   line is only an amount; the next line is then consumed.
///
/// A date without a year (e.g. `05/10`) cannot be told apart from a `5/10` marker; such lines are read
/// as installments.
public enum StatementParser {
    /// Returns the installment candidates found in `lines`, in the order they appear.
    public static func parse(lines: [String]) -> [InstallmentCandidate] {
        // NSRegularExpression'ları her çağrıda kuruyoruz: global durum yok, eşzamanlılık derdi yok.
        let patterns = Patterns()
        let lines = lines.map(normalized)
        var candidates: [InstallmentCandidate] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            guard var scan = LineScan(line: line, patterns: patterns) else { continue }
            // Satır kırılması: işaret var ama tutar yoksa, sonraki satır yalnızca tutarsa onu al.
            if scan.amounts.isEmpty, index < lines.count, let amount = patterns.amountOnly(in: lines[index]) {
                scan.amounts = [amount]
                index += 1
            }
            if let candidate = scan.candidate() {
                candidates.append(candidate)
            }
        }
        return candidates
    }

    // NFC (ayrık "I + nokta"yı "İ" yapar), tüm boşluk türlerini tek boşluğa indir, kenarları kırp.
    private static func normalized(_ line: String) -> String {
        line.precomposedStringWithCanonicalMapping
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - Satır taraması

/// One amount found on a line.
private struct AmountMatch {
    let value: Decimal
    let isNegative: Bool
}

/// What a single line contains; `nil` when the line can never be a candidate.
private struct LineScan {
    let current: Int
    let total: Int
    let date: StatementDate?
    var amounts: [AmountMatch]
    let merchant: String

    init?(line: String, patterns: Patterns) {
        guard !line.isEmpty else { return nil }
        let folded = Folding.fold(line)
        guard !Folding.isIgnored(folded) else { return nil }

        // Çalışma metni: bulunan parçalar boşlukla silinir, böylece sonraki aramalar onları görmez.
        // Katlama UTF-16 uzunluğunu koruduğu için aralıklar orijinal satırda da geçerli.
        let work = NSMutableString(string: folded)
        var removed: [NSRange] = []

        let dates = patterns.date.matches(in: work as String, range: NSRange(location: 0, length: work.length))
        var date: StatementDate?
        for match in dates {
            if date == nil { date = patterns.statementDate(from: match, in: work as String) }
            removed.append(match.range)
        }
        Patterns.blank(dates.map(\.range), in: work)

        guard let marker = patterns.marker(in: work as String) else { return nil }
        guard (2...InstallmentPlan.supportedCounts.upperBound).contains(marker.total),
              (1...marker.total).contains(marker.current)
        else { return nil }
        removed.append(marker.range)
        Patterns.blank([marker.range], in: work)

        let amounts = patterns.amounts(in: work as String)
        removed.append(contentsOf: amounts.map(\.range))

        self.current = marker.current
        self.total = marker.total
        self.date = date
        self.amounts = amounts.map(\.amount)
        self.merchant = Folding.merchant(from: line, removing: removed)
    }

    func candidate() -> InstallmentCandidate? {
        // Tahmin yok: tutar yoksa, eksi/sıfırsa ya da firma adı boşsa aday değil.
        guard let amount = amounts.last, !amount.isNegative, amount.value > 0 else { return nil }
        guard merchant.contains(where: \.isLetter) else { return nil }
        return InstallmentCandidate(
            merchant: merchant, installmentAmount: amount.value,
            currentInstallment: current, totalInstallments: total, date: date
        )
    }
}

// MARK: - Desenler

private struct Patterns {
    struct Marker {
        let current: Int
        let total: Int
        let range: NSRange
    }

    // Tüm desenler katlanmış (küçük harf, Türkçe harfler ASCII'ye indirilmiş) metinde çalışır.
    let date: NSRegularExpression
    let markers: [NSRegularExpression]
    let amount: NSRegularExpression

    init() {
        // 12.10.2026, 12/10/2026 (ve 12.10.26); başka bir sayının ya da tutarın parçası değilse.
        date = Patterns.regex(#"(?<![\d/.,])(\d{1,2})[./](\d{1,2})[./](\d{4}|\d{2})(?![\d/]|[.,]\d)"#)
        // Öncelik sırası: en açık desen önce; ilk eşleşen desen kazanır.
        markers = [
            // 3. taksit / 6
            Patterns.regex(#"(?<!\d)(\d{1,2})\s*\.\s*taksit\s*/\s*(\d{1,2})(?!\d)"#),
            // Taksit 3/6, Taksit: 3/6
            Patterns.regex(#"taksit\s*:?\s*(\d{1,2})\s*/\s*(\d{1,2})(?!\d)"#),
            // (3/6)
            Patterns.regex(#"\(\s*(\d{1,2})\s*/\s*(\d{1,2})\s*\)"#),
            // 3/6 (tarih ya da kesirli sayı parçası değilse)
            Patterns.regex(#"(?<![\d/.,])(\d{1,2})\s*/\s*(\d{1,2})(?![\d/]|[.,]\d)"#),
        ]
        // [-]₺[-]1.234,56[-] [TL|TRY|₺]; tam kısımda ilk karakter gerçek rakam, sonra OCR'ın "O"su da rakam sayılır.
        amount = Patterns.regex(
            #"(?<![\p{L}\d.,])(-?)(?:₺\s?)?(-?)([0-9][0-9o]{0,2}(?:\.[0-9o]{3})+|[0-9][0-9o]*),([0-9o]{2})(-?)(?:\s?(?:tl|try|₺))?(?![\p{L}\d])"#
        )
    }

    func statementDate(from match: NSTextCheckingResult, in text: String) -> StatementDate? {
        let string = text as NSString
        let yearText = string.substring(with: match.range(at: 3))
        // İki haneli yılı yüzyıl tahmin etmemek için tarih olarak almıyoruz (yine de işaret sayılmaz).
        guard yearText.count == 4,
              let day = Int(string.substring(with: match.range(at: 1))),
              let month = Int(string.substring(with: match.range(at: 2))),
              let year = Int(yearText)
        else { return nil }
        return StatementDate(year: year, month: month, day: day)
    }

    func marker(in text: String) -> Marker? {
        let string = text as NSString
        let all = NSRange(location: 0, length: string.length)
        for pattern in markers {
            let found = pattern.matches(in: text, range: all).compactMap { match -> Marker? in
                guard let current = Int(string.substring(with: match.range(at: 1))),
                      let total = Int(string.substring(with: match.range(at: 2)))
                else { return nil }
                return Marker(current: current, total: total, range: match.range)
            }
            guard let first = found.first else { continue }
            // Aynı satırda farklı iki işaret belirsizdir; tahmin etmek yerine satırı atlıyoruz.
            guard found.allSatisfy({ $0.current == first.current && $0.total == first.total }) else { return nil }
            return first
        }
        return nil
    }

    func amounts(in text: String) -> [(amount: AmountMatch, range: NSRange)] {
        let string = text as NSString
        return amount.matches(in: text, range: NSRange(location: 0, length: string.length)).compactMap { match in
            let integer = string.substring(with: match.range(at: 3))
                .replacingOccurrences(of: "o", with: "0")
                .replacingOccurrences(of: ".", with: "")
            let fraction = string.substring(with: match.range(at: 4)).replacingOccurrences(of: "o", with: "0")
            guard let value = Decimal(string: "\(integer).\(fraction)", locale: Locale(identifier: "en_US_POSIX"))
            else { return nil }
            let isNegative = [1, 2, 5].contains { match.range(at: $0).length > 0 }
            return (AmountMatch(value: value, isNegative: isNegative), match.range)
        }
    }

    /// The amount when `line` holds nothing but one amount (and currency), else `nil`.
    func amountOnly(in line: String) -> AmountMatch? {
        let work = NSMutableString(string: Folding.fold(line))
        let found = amounts(in: work as String)
        guard found.count == 1 else { return nil }
        Patterns.blank([found[0].range], in: work)
        let rest = (work as String).trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        return rest.isEmpty ? found[0].amount : nil
    }

    static func blank(_ ranges: [NSRange], in text: NSMutableString) {
        for range in ranges {
            text.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Desenler sabit; derlenemezlerse bu bir programlama hatasıdır.
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Invalid statement pattern: \(pattern)")
        }
    }
}

// MARK: - Katlama ve gürültü

private enum Folding {
    // Kelime başıyla eşleşen anahtarlar: toplam, faiz, ücret, KKDF, BSMV, gecikme, asgari, özet satırları.
    private static let ignoredPrefixes = [
        "toplam", "asgari", "faiz", "ucret", "kkdf", "bsmv", "gecikme", "bakiye", "borc", "ekstre", "donem",
        "odenecek",
    ]
    // "faizsiz taksit" gerçek bir taksit satırıdır; faiz satırı sayılmaz.
    private static let allowedWords: Set<String> = ["faizsiz"]
    private static let ignoredPhrases = ["son odeme", "hesap kesim"]
    // Firma adından atılan dolgu kelimeleri.
    private static let noiseWords: Set<String> = [
        "tl", "try", "₺", "taksit", "taksiti", "taksitli", "taks", "islem", "islemi", "tutar", "tutari", "faizsiz",
    ]

    /// Lowercases and maps Turkish letters to ASCII, keeping the UTF-16 length of every scalar.
    static func fold(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            scalars.append(fold(scalar))
        }
        return String(scalars)
    }

    private static func fold(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        switch scalar {
        case "İ", "I", "ı": return "i"
        case "Ü", "ü": return "u"
        case "Ö", "ö": return "o"
        case "Ç", "ç": return "c"
        case "Ş", "ş": return "s"
        case "Ğ", "ğ": return "g"
        // OCR'ın ürettiği eksi ve tire türleri.
        case "\u{2212}", "\u{2010}", "\u{2011}", "\u{2013}", "\u{2014}": return "-"
        default:
            // Aralıklar orijinal satıra taşınabilsin diye yalnızca uzunluğu aynı kalan küçük harfe çeviriyoruz.
            let lower = scalar.properties.lowercaseMapping.unicodeScalars
            if lower.count == 1, let first = lower.first, first.utf16.count == scalar.utf16.count {
                return first
            }
            return scalar
        }
    }

    static func isIgnored(_ folded: String) -> Bool {
        if ignoredPhrases.contains(where: { folded.contains($0) }) { return true }
        return words(in: folded).contains { word in
            !allowedWords.contains(word) && ignoredPrefixes.contains(where: word.hasPrefix)
        }
    }

    /// The merchant text: `line` without `removed`, noise words and punctuation-only tokens.
    static func merchant(from line: String, removing removed: [NSRange]) -> String {
        let text = NSMutableString(string: line)
        Patterns.blank(removed, in: text)
        return (text as String)
            .split(separator: " ")
            .filter { token in
                let bare = fold(String(token)).trimmingCharacters(in: .punctuationCharacters.union(.symbols))
                return !bare.isEmpty && !noiseWords.contains(bare)
            }
            .joined(separator: " ")
    }

    private static func words(in folded: String) -> [String] {
        folded.split(whereSeparator: { !$0.isLetter }).map(String.init)
    }
}
