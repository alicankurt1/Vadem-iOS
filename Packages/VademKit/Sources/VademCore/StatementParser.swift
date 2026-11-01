import Foundation

/// Finds installment lines, and the statement total with its due date, in the text of a credit card statement.
///
/// The input is plain text lines, as OCR or PDF text extraction returns them. The parser never
/// guesses: a line becomes an ``InstallmentCandidate`` only when it has a clear installment marker
/// and an amount. Rules:
/// - **Marker**: `3/6`, `3. taksit / 6`, `Taksit 3/6`, `(3/6)` or `<monthly>x<count>=<total> <k>.Taksit`
///   (e.g. `1.878,96x9=16.910,00 1.Taksit`; any case, Turkish `İ`/`ı` aware, with or without a space before
///   `Taksit`). Valid only when `1 ≤ current ≤ total`, `total ≥ 2` and `total` is in
///   ``InstallmentPlan/supportedCounts``. Two different markers on one line make it ambiguous, so it is skipped.
///   In the `x…=` form, current is `k`, total is `count` and the amount is `monthly`; `monthly × count` must
///   equal `total` within 1% of `total` (statements round and add small extras), else the line is skipped.
/// - **Amount**: Turkish format with 2 fraction digits (`234,56`, `1.234,56`, `1.234,56 TL`, `₺1.234,56`).
///   When a line has several amounts, the **last** one is the installment amount (statements print the
///   purchase total first and the installment amount in the last column). A negative (credit) or zero
///   amount means no candidate. Inside amounts the letter `O` is read as `0` (OCR noise). The `x…=` form
///   carries its own amount (`monthly`); other amounts on its line (e.g. a small bonus column) are ignored.
/// - **Date**: `12.10.2026`, `12/10/2026` or `16 Ekim 2026` (all twelve Turkish month names, any case);
///   optional. Dates are never read as markers. A two-digit year (`12.10.26`) is still recognized as a date
///   (so it is not read as a marker), but the century is not guessed: the candidate's `date` is `nil`.
///   The candidate's date is the last date before the marker, else the first date on the line.
/// - **Merchant**: what is left after removing the date, marker, amounts, currency and noise words;
///   it must contain a letter. When a date comes before the marker, the merchant is taken from the text
///   after that date (PDF extraction can join a section header to the first row; the header is dropped).
/// - **Skipped lines**: totals, interest and fees (faiz, ücret, KKDF, BSMV, gecikme), minimum payment
///   and statement summary lines, even when they contain something like `1/2`. Short or ambiguous keys
///   (toplam, ücret, borç, dönem, ekstre, bakiye, ...) match whole words and their common inflections only,
///   so merchant names that merely start with them (e.g. `BORCELIK`, `UCRETSIZ`) are kept. When a date comes
///   before the marker, only the text from that date on is checked, so a joined header does not drop the row.
/// - **Broken lines**: a line with a marker but no amount takes its amount from the next line when that
///   line is only an amount; the next line is then consumed.
///
/// A date without a year (e.g. `05/10`) cannot be told apart from a `5/10` marker; such lines are read
/// as installments.
///
/// **Statement summary** (``parseStatement(lines:)``): the total is the first amount after `Dönem Borcunuz`
/// (else `Toplam Borcunuz`) on its line, before any `Asgari` (minimum payment) label, or the next line when
/// that line is only an amount; it must be greater than zero. The due date is the first date after
/// `Son Ödeme Tarihi`, or the next line when that line is only a date. Without both there is no summary.
public enum StatementParser {
    /// Returns the installment candidates found in `lines`, in the order they appear.
    public static func parse(lines: [String]) -> [InstallmentCandidate] {
        candidates(in: lines.map(normalized), patterns: Patterns())
    }

    /// Returns the installment candidates (like ``parse(lines:)``) and the statement summary found in `lines`.
    public static func parseStatement(lines: [String]) -> StatementParseResult {
        let patterns = Patterns()
        let lines = lines.map(normalized)
        return StatementParseResult(
            candidates: candidates(in: lines, patterns: patterns),
            summary: SummaryScan.summary(in: lines, patterns: patterns)
        )
    }

    private static func candidates(in lines: [String], patterns: Patterns) -> [InstallmentCandidate] {
        // NSRegularExpression'ları her çağrıda kuruyoruz: global durum yok, eşzamanlılık derdi yok.
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

        // Çalışma metni: bulunan parçalar boşlukla silinir, böylece sonraki aramalar onları görmez.
        // Katlama UTF-16 uzunluğunu koruduğu için aralıklar orijinal satırda da geçerli.
        let work = NSMutableString(string: folded)
        var removed: [NSRange] = []

        let dates = patterns.dates(in: folded)
        removed.append(contentsOf: dates.map(\.range))
        Patterns.blank(dates.map(\.range), in: work)

        guard let marker = patterns.marker(in: work as String) else {
            // İşaret yoksa aday da yok; atlanacak satır olup olmaması fark etmez.
            return nil
        }
        guard (2...InstallmentPlan.supportedCounts.upperBound).contains(marker.total),
              (1...marker.total).contains(marker.current)
        else { return nil }
        removed.append(marker.range)
        Patterns.blank([marker.range], in: work)

        // İşaretten önceki son tarih satırın kendi tarihidir; öncesindeki metin birleşmiş bir başlık olabilir.
        let anchor = dates.last { $0.range.upperBound <= marker.range.location }
        let fromAnchor = anchor.map { (folded as NSString).substring(from: $0.range.location) } ?? folded
        guard !Folding.isIgnored(fromAnchor) else { return nil }

        let found = patterns.amounts(in: work as String)
        removed.append(contentsOf: found.map(\.range))

        var merchant = ""
        if let anchor {
            // Firma adı tarihten sonra aranır; başlık metni asla firma adı olmaz.
            let header = NSRange(location: 0, length: anchor.range.upperBound)
            merchant = Folding.merchant(from: line, removing: removed + [header])
        }
        if !merchant.contains(where: \.isLetter) {
            // Tarihten sonra ad yoksa (ör. ad tarihten önce), satırın tamamı atlama kurallarına uymalı.
            guard anchor == nil || !Folding.isIgnored(folded) else { return nil }
            merchant = Folding.merchant(from: line, removing: removed)
        }

        self.current = marker.current
        self.total = marker.total
        self.date = anchor.map(\.date) ?? dates.lazy.compactMap(\.date).first
        // "x…=" biçimi tutarını kendisi taşır; satırdaki diğer tutarlar (ör. bonus sütunu) kullanılmaz.
        self.amounts = marker.amount.map { [AmountMatch(value: $0, isNegative: false)] } ?? found.map(\.amount)
        self.merchant = merchant
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
        /// The per-installment amount the marker itself states (`x…=` form), else `nil`.
        var amount: Decimal?
    }

    struct DateMatch {
        let range: NSRange
        /// The date, or `nil` when it is not a real date or has a two-digit year.
        let date: StatementDate?
    }

    // Tüm desenler katlanmış (küçük harf, Türkçe harfler ASCII'ye indirilmiş) metinde çalışır.
    let date: NSRegularExpression
    let monthNameDate: NSRegularExpression
    let statedMarker: NSRegularExpression
    let markers: [NSRegularExpression]
    let amount: NSRegularExpression

    // Katlanmış Türkçe ay adları, sırayla (ocak = 1).
    static let monthNames = [
        "ocak", "subat", "mart", "nisan", "mayis", "haziran", "temmuz", "agustos", "eylul", "ekim", "kasim", "aralik",
    ]
    // Türk biçimli tutarın sayı kısmı (eksi ve para birimi olmadan); OCR'ın "O"su da rakam sayılır.
    private static let number = #"[0-9][0-9o]{0,2}(?:\.[0-9o]{3})+,[0-9o]{2}|[0-9][0-9o]*,[0-9o]{2}"#

    init() {
        // 12.10.2026, 12/10/2026 (ve 12.10.26); başka bir sayının ya da tutarın parçası değilse.
        date = Patterns.regex(#"(?<![\d/.,])(\d{1,2})[./](\d{1,2})[./](\d{4}|\d{2})(?![\d/]|[.,]\d)"#)
        // 16 ekim 2026: ay adı tam kelime, yıl dört haneli.
        monthNameDate = Patterns.regex(
            #"(?<![\p{L}\d])(\d{1,2})\s+("# + Patterns.monthNames.joined(separator: "|") + #")\s+(\d{4})(?![\p{L}\d])"#
        )
        // 1.878,96x9=16.910,00 1.taksit: aylık tutar, taksit sayısı, toplam ve şimdiki taksit.
        statedMarker = Patterns.regex(
            #"(?<![\p{L}\d.,])("# + Patterns.number + #")\s*[x×]\s*(\d{1,2})\s*=\s*("# + Patterns.number
                + #")\s*(\d{1,2})\s*\.\s*taksit"#
        )
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

    /// Every date in the folded `text` (numeric and month-name), in the order they appear.
    func dates(in text: String) -> [DateMatch] {
        let string = text as NSString
        let all = NSRange(location: 0, length: string.length)
        let numeric = date.matches(in: text, range: all).map { match in
            DateMatch(range: match.range, date: statementDate(from: match, in: text))
        }
        let named = monthNameDate.matches(in: text, range: all).map { match -> DateMatch in
            let monthName = string.substring(with: match.range(at: 2))
            let month = Patterns.monthNames.firstIndex(of: monthName).map { $0 + 1 }
            let day = Int(string.substring(with: match.range(at: 1)))
            let year = Int(string.substring(with: match.range(at: 3)))
            guard let month, let day, let year else { return DateMatch(range: match.range, date: nil) }
            return DateMatch(range: match.range, date: StatementDate(year: year, month: month, day: day))
        }
        return (numeric + named).sorted { $0.range.location < $1.range.location }
    }

    private func statementDate(from match: NSTextCheckingResult, in text: String) -> StatementDate? {
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
        let stated = statedMarker.matches(in: text, range: all)
        if let first = stated.first {
            // Aynı satırda farklı iki "x…=" işareti belirsizdir; aritmetiği tutmayan işaret de atlanır.
            let values = stated.map { match in (0...4).map { string.substring(with: match.range(at: $0)) } }
            guard values.allSatisfy({ $0.dropFirst() == values[0].dropFirst() }) else { return nil }
            return parsedStatedMarker(first, in: string)
        }
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

    // Aylık × sayı, basılı toplamdan en çok %1 sapabilir (yuvarlama ve küçük ekler).
    private func parsedStatedMarker(_ match: NSTextCheckingResult, in string: NSString) -> Marker? {
        guard let monthly = Patterns.value(of: string.substring(with: match.range(at: 1))),
              let count = Int(string.substring(with: match.range(at: 2))),
              let planTotal = Patterns.value(of: string.substring(with: match.range(at: 3))),
              let current = Int(string.substring(with: match.range(at: 4)))
        else { return nil }
        let difference = monthly * Decimal(count) - planTotal
        let tolerance = planTotal / 100
        guard difference <= tolerance, -difference <= tolerance else { return nil }
        return Marker(current: current, total: count, range: match.range, amount: monthly)
    }

    // "1.878,96" → 1878.96; OCR'ın "o"su sıfır sayılır.
    private static func value(of number: String) -> Decimal? {
        let parts = number.replacingOccurrences(of: "o", with: "0").split(separator: ",")
        guard parts.count == 2 else { return nil }
        let integer = parts[0].replacingOccurrences(of: ".", with: "")
        return Decimal(string: "\(integer).\(parts[1])", locale: Locale(identifier: "en_US_POSIX"))
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

    /// The date when `line` holds nothing but one real date, else `nil`.
    func dateOnly(in line: String) -> StatementDate? {
        let work = NSMutableString(string: Folding.fold(line))
        let found = dates(in: work as String)
        guard found.count == 1, let date = found[0].date else { return nil }
        Patterns.blank([found[0].range], in: work)
        let rest = (work as String).trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        return rest.isEmpty ? date : nil
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

// MARK: - Ekstre özeti

/// Finds the statement total and due date; never the minimum payment.
private enum SummaryScan {
    // Öncelik sırası: dönem borcu, yoksa toplam borç.
    private static let totalLabels = ["donem borcunuz", "toplam borcunuz"]
    private static let dueDateLabel = "son odeme tarihi"
    // Asgari ödeme aynı satıra düşerse ondan sonraki tutarlar alınmaz.
    private static let minimumPaymentLabel = "asgari"

    static func summary(in lines: [String], patterns: Patterns) -> StatementSummary? {
        let folded = lines.map(Folding.fold)
        guard let total = totalLabels.lazy.compactMap({ total(after: $0, in: folded, patterns: patterns) }).first,
              let dueDate = dueDate(in: folded, patterns: patterns)
        else { return nil }
        return StatementSummary(total: total, dueDate: dueDate)
    }

    // Etiketli ilk satır kullanılır: etiketten sonraki ilk tutar, yoksa yalnızca tutar olan sonraki satır.
    private static func total(after label: String, in lines: [String], patterns: Patterns) -> Decimal? {
        guard let index = lines.firstIndex(where: { $0.contains(label) }),
              var rest = text(after: label, in: lines[index])
        else { return nil }
        if let minimum = rest.range(of: minimumPaymentLabel) {
            rest = String(rest[..<minimum.lowerBound])
        }
        let found = patterns.amounts(in: rest)
        let amount: AmountMatch?
        if let first = found.first {
            amount = first.amount
        } else if index + 1 < lines.count, patterns.amounts(in: lines[index]).isEmpty {
            // PDF sütunları ayrılınca tutar alt satıra düşebilir; o satır yalnızca tutar olmalı.
            amount = patterns.amountOnly(in: lines[index + 1])
        } else {
            amount = nil
        }
        guard let amount, !amount.isNegative, amount.value > 0 else { return nil }
        return amount.value
    }

    private static func dueDate(in lines: [String], patterns: Patterns) -> StatementDate? {
        guard let index = lines.firstIndex(where: { $0.contains(dueDateLabel) }),
              let rest = text(after: dueDateLabel, in: lines[index])
        else { return nil }
        let found = patterns.dates(in: rest)
        if !found.isEmpty { return found.lazy.compactMap(\.date).first }
        guard index + 1 < lines.count, patterns.dates(in: lines[index]).isEmpty else { return nil }
        return patterns.dateOnly(in: lines[index + 1])
    }

    private static func text(after label: String, in line: String) -> String? {
        line.range(of: label).map { String(line[$0.upperBound...]) }
    }
}

// MARK: - Katlama ve gürültü

private enum Folding {
    // Kökü belirsiz olmayan anahtarlar: kelime başıyla eşleşir ("faizi", "gecikmeli" de yakalanır).
    private static let ignoredStems = ["faiz", "gecikme", "kkdf", "bsmv"]
    // "faizsiz taksit" gerçek bir taksit satırıdır; faiz satırı sayılmaz.
    private static let allowedStems = ["faizsiz"]
    // Kısa ya da firma adına gömülebilen anahtarlar (BORCELIK, DONEMSEL, UCRETSIZ, EKSTRELI) yalnızca
    // tam kelime olarak eşleşir; ekstrelerde geçen çekimli halleri de listede.
    private static let ignoredWords: Set<String> = [
        "toplam", "toplami", "toplamlar", "toplamlari",
        "asgari",
        "ucret", "ucreti", "ucretler", "ucretleri",
        "bakiye", "bakiyesi", "bakiyeniz",
        "borc", "borcu", "borcunuz", "borclar", "borclari",
        "ekstre", "ekstresi", "ekstrenin", "ekstreniz",
        "donem", "donemi", "donemin", "donemki",
        "odenecek",
    ]
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
            if ignoredWords.contains(word) { return true }
            guard !allowedStems.contains(where: word.hasPrefix) else { return false }
            return ignoredStems.contains(where: word.hasPrefix)
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
