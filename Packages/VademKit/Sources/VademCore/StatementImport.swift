import Foundation

/// Turning a confirmed ``InstallmentCandidate`` into an ``InstallmentItem``.
///
/// The statement shows one installment (`current/total`) of a plan. The plan is rebuilt so that this
/// installment falls in the chosen statement month: the first payment is `currentInstallment - 1` months
/// earlier and the remaining ones continue monthly. The plan total is `installmentAmount × totalInstallments`
/// (the amount rounded to kuruş first), so every payment equals the statement's amount.
extension InstallmentCandidate {
    /// ``merchant`` as an item title: runs of whitespace become one space, the ends are trimmed and the
    /// text is cut to ``InstallmentItem/maxTitleLength`` characters. May be empty (OCR found no name).
    public var suggestedTitle: String {
        StatementImport.title(fromMerchant: merchant)
    }

    /// `true` when ``currentInstallment`` is in `1...totalInstallments` and ``totalInstallments``
    /// is in ``InstallmentPlan/supportedCounts``.
    public var hasValidInstallmentNumbers: Bool {
        InstallmentPlan.supportedCounts.contains(totalInstallments)
            && (1...totalInstallments).contains(currentInstallment)
    }

    /// The payments left from the statement month on, counting the statement's own installment
    /// (`3/6` → 4: installments 3, 4, 5 and 6); `0` when the installment numbers are invalid.
    public var remainingInstallments: Int {
        hasValidInstallmentNumbers ? totalInstallments - currentInstallment + 1 : 0
    }

    /// The month of the plan's first payment when the current installment falls in `statementMonth`,
    /// or `nil` when the installment numbers are invalid or the month would be before January of year 1.
    public func firstMonth(statementMonth: YearMonth) -> YearMonth? {
        guard hasValidInstallmentNumbers else { return nil }
        let back = currentInstallment - 1
        // adding(months:) aralık dışında durur; önce sınır kontrol edilir.
        guard StatementImport.firstSupportedMonth.months(until: statementMonth) >= back else { return nil }
        return statementMonth.adding(months: -back)
    }

    /// The month of the plan's last payment when the current installment falls in `statementMonth`,
    /// or `nil` when the installment numbers are invalid or the month would be after December 9999.
    public func endMonth(statementMonth: YearMonth) -> YearMonth? {
        guard hasValidInstallmentNumbers else { return nil }
        let ahead = totalInstallments - currentInstallment
        guard statementMonth.months(until: StatementImport.lastSupportedMonth) >= ahead else { return nil }
        return statementMonth.adding(months: ahead)
    }

    /// The draft of the plan, with ``suggestedTitle``, total `installmentAmount × totalInstallments` and the
    /// first month from ``firstMonth(statementMonth:)``; `nil` when the installment numbers are invalid or
    /// the months fall outside ``YearMonth/supportedYears``. The draft's own ``InstallmentDraft/errors``
    /// cover the title and the amount.
    public func draft(cardID: Card.ID?, paymentDay: Int, statementMonth: YearMonth) -> InstallmentDraft? {
        guard let firstMonth = firstMonth(statementMonth: statementMonth),
              endMonth(statementMonth: statementMonth) != nil else { return nil }
        // Taksit tutarı önce kuruşa yuvarlanır; böylece her taksit ekstredeki tutara birebir eşit olur.
        let total = Money(installmentAmount).amount * Decimal(totalInstallments)
        return InstallmentDraft(
            title: suggestedTitle, cardID: cardID, paymentDay: paymentDay,
            total: total, count: totalInstallments, firstMonth: firstMonth
        )
    }

    /// The installment item for `cardID` (or, without a card, paid on `paymentDay`) whose current installment
    /// falls in `statementMonth`; `nil` when ``draft(cardID:paymentDay:statementMonth:)`` is `nil` or invalid.
    public func makeItem(
        cardID: Card.ID?, paymentDay: Int = InstallmentItem.supportedPaymentDays.lowerBound,
        statementMonth: YearMonth, id: UUID = UUID()
    ) -> InstallmentItem? {
        draft(cardID: cardID, paymentDay: paymentDay, statementMonth: statementMonth)?.makeItem(id: id)
    }

    /// `true` when one of `existing` looks like the same plan: the same card (`nil` matches card-less items),
    /// a similar title (``StatementImport/isSimilarTitle(_:_:)``), the same number of installments and the same
    /// per-installment amount (rounded to kuruş).
    public func isPossibleDuplicate(of existing: [InstallmentItem], cardID: Card.ID?) -> Bool {
        let amount = Money(installmentAmount)
        return existing.contains { item in
            guard item.cardID == cardID, item.plan.count == totalInstallments else { return false }
            // İlk taksit artan kuruşları taşıyabilir; ilk ya da son taksitten biri eşitse aynı tutar sayılır.
            let plan = item.plan
            guard plan.amount(in: plan.firstMonth) == amount || plan.amount(in: plan.lastMonth) == amount else {
                return false
            }
            return StatementImport.isSimilarTitle(merchant, item.title)
        }
    }
}

/// Text rules of the statement import, shared by ``InstallmentCandidate``'s helpers.
public enum StatementImport {
    /// `merchant` as an item title: runs of whitespace become one space, the ends are trimmed and the
    /// text is cut to ``InstallmentItem/maxTitleLength`` characters.
    public static func title(fromMerchant merchant: String) -> String {
        let words = merchant.split(whereSeparator: { $0.isWhitespace })
        let joined = words.joined(separator: " ")
        // Kesilen metnin sonunda boşluk kalmasın diye kesildikten sonra yeniden kırpılır.
        return String(joined.prefix(InstallmentItem.maxTitleLength)).trimmingCharacters(in: .whitespaces)
    }

    /// `true` when the two titles are equal, or one contains the other, after folding: case and diacritics
    /// are ignored (Turkish `ı` and `İ` count as `i`), runs of whitespace become one space and the ends are
    /// trimmed. An empty title is never similar.
    public static func isSimilarTitle(_ lhs: String, _ rhs: String) -> Bool {
        let a = folded(lhs)
        let b = folded(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || a.contains(b) || b.contains(a)
    }

    // Karşılaştırma biçimi: Türkçe noktalı/noktasız i önce eşitlenir, sonra büyük-küçük harf ve aksan atılır.
    static func folded(_ text: String) -> String {
        let dotless = text.replacingOccurrences(of: "ı", with: "i").replacingOccurrences(of: "İ", with: "i")
        let folded = dotless.folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
        )
        return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static let firstSupportedMonth = YearMonth(year: YearMonth.supportedYears.lowerBound, month: 1)!
    static let lastSupportedMonth = YearMonth(year: YearMonth.supportedYears.upperBound, month: 12)!
}
