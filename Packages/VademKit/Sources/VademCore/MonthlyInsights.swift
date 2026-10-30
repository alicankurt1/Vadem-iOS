import Foundation

/// One noteworthy fact about a month's payments compared with the month before (pure value).
///
/// The identity comes from the kind and the month (``id``), so the same insight computed
/// twice is the same value and can be stored (e.g. in an inbox) without duplicates.
public struct MonthlyInsight: Sendable, Hashable, Identifiable {
    /// What the insight is about; the order of ``allCases`` is the importance ranking.
    public enum Kind: String, Sendable, Hashable, CaseIterable, Comparable {
        /// The month's total changed by at least ``MonthlyInsightCalculator/changeThreshold``.
        case totalChange
        /// One or more installment plans made their last payment in the previous month.
        case installmentEnded

        /// Lower is more important: ``totalChange`` comes before ``installmentEnded``.
        public var rank: Int {
            Kind.allCases.firstIndex(of: self) ?? Kind.allCases.count
        }

        public static func < (lhs: Kind, rhs: Kind) -> Bool {
            lhs.rank < rhs.rank
        }
    }

    /// The facts behind the insight.
    public enum Detail: Sendable, Hashable {
        /// The month's total went from `previous` to `current`; `percent` is the signed,
        /// rounded change (see ``MonthlyInsightCalculator/percentChange(from:to:)``).
        case totalChange(previous: Money, current: Money, percent: Int)
        /// The plans whose last payment was due in the previous month, in schedule order,
        /// and the exact sum of those last payments (the amount paid less this month).
        case installmentEnded(titles: [String], amount: Money)
    }

    /// A deterministic id: `insight-YYYY-MM-<kind>`, e.g. `insight-2026-11-totalChange`.
    public let id: String
    /// The month the insight is about (the "this month" of the comparison).
    public let month: YearMonth
    /// The facts behind the insight.
    public let detail: Detail

    /// The kind of ``detail``.
    public var kind: Kind { MonthlyInsight.kind(of: detail) }

    /// Creates an insight about `month`; ``id`` is derived from the kind and the month.
    public init(month: YearMonth, detail: Detail) {
        self.month = month
        self.detail = detail
        self.id = MonthlyInsight.id(of: MonthlyInsight.kind(of: detail), in: month)
    }

    /// The id of an insight of `kind` about `month`: `insight-YYYY-MM-<kind>`.
    public static func id(of kind: Kind, in month: YearMonth) -> String {
        "\(idPrefix(for: month))-\(kind.rawValue)"
    }

    /// The month part of every insight id: `insight-YYYY-MM`.
    public static func idPrefix(for month: YearMonth) -> String {
        "insight-\(padded(month.year, to: 4))-\(padded(month.month, to: 2))"
    }

    private static func kind(of detail: Detail) -> Kind {
        switch detail {
        case .totalChange: return .totalChange
        case .installmentEnded: return .installmentEnded
        }
    }

    private static func padded(_ value: Int, to width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}

/// Compares a month's payments with the previous month's (pure; no side effects).
///
/// Months are the **due** months of ``MonthlySchedule`` (ADR-0002); one-time payments count in
/// the month they are due. Insights:
/// - ``MonthlyInsight/Kind/totalChange``: the month's total differs from the previous month's
///   by at least ``changeThreshold`` (exact ratio, before rounding). Never produced when the
///   previous total is zero (or below), since no percentage exists then.
/// - ``MonthlyInsight/Kind/installmentEnded``: installment plans whose **last** payment was due
///   in the previous month; one insight covers every such plan.
public enum MonthlyInsightCalculator {
    /// The smallest relative change of the total that is reported: 20% (as a fraction).
    public static let changeThreshold: Decimal = Decimal(sign: .plus, exponent: -1, significand: 2)

    /// The insights about `month`, most important first (see ``MonthlyInsight/Kind/rank``).
    ///
    /// Returns an empty array for the first supported month (0001-01), which has no previous month.
    public static func insights(
        for month: YearMonth,
        cards: [Card],
        installments: [InstallmentItem],
        subscriptions: [SubscriptionItem],
        oneTimePayments: [OneTimePaymentItem] = []
    ) -> [MonthlyInsight] {
        // 0001-01'in önceki ayı yok; adding(months:) aralık dışında çöker.
        let first = YearMonth(year: YearMonth.supportedYears.lowerBound, month: 1)!
        guard first < month else { return [] }
        let previousMonth = month.adding(months: -1)

        let current = MonthlySchedule(
            month: month, cards: cards, installments: installments,
            subscriptions: subscriptions, oneTimePayments: oneTimePayments
        )
        let previous = MonthlySchedule(
            month: previousMonth, cards: cards, installments: installments,
            subscriptions: subscriptions, oneTimePayments: oneTimePayments
        )

        var insights: [MonthlyInsight] = []
        if let detail = totalChange(previous: previous.total, current: current.total) {
            insights.append(MonthlyInsight(month: month, detail: detail))
        }
        if let detail = installmentEnded(in: previous) {
            insights.append(MonthlyInsight(month: month, detail: detail))
        }
        // Önem sırası: türün sırası (toplam değişimi önce); her türden en fazla bir içgörü vardır.
        return insights.sorted { $0.kind < $1.kind }
    }

    /// The most important insight about `month`, or `nil` when there is none.
    public static func topInsight(
        for month: YearMonth,
        cards: [Card],
        installments: [InstallmentItem],
        subscriptions: [SubscriptionItem],
        oneTimePayments: [OneTimePaymentItem] = []
    ) -> MonthlyInsight? {
        insights(
            for: month, cards: cards, installments: installments,
            subscriptions: subscriptions, oneTimePayments: oneTimePayments
        ).first
    }

    /// The signed change from `previous` to `current` in whole percent, rounded half away from
    /// zero (`12.5% → 13`, `-12.5% → -13`); `nil` when `previous` is zero or below.
    public static func percentChange(from previous: Money, to current: Money) -> Int? {
        guard let ratio = ratio(from: previous, to: current) else { return nil }
        var input = ratio * 100
        var result = Decimal()
        // .plain: yarımda sıfırdan uzağa (Money ile aynı kural).
        NSDecimalRound(&result, &input, 0, .plain)
        return NSDecimalNumber(decimal: result).intValue
    }

    // Değişim oranı (ör. 0.5 = %50). Önceki toplam sıfır ya da negatifse yüzde yoktur.
    private static func ratio(from previous: Money, to current: Money) -> Decimal? {
        guard previous.amount > 0 else { return nil }
        return (current.amount - previous.amount) / previous.amount
    }

    // Eşik yuvarlanmamış oranla karşılaştırılır: %19,6 değişim bildirilmez.
    private static func totalChange(previous: Money, current: Money) -> MonthlyInsight.Detail? {
        guard let ratio = ratio(from: previous, to: current),
              abs(ratio) >= changeThreshold,
              let percent = percentChange(from: previous, to: current) else { return nil }
        return .totalChange(previous: previous, current: current, percent: percent)
    }

    // Önceki ayda son taksiti (numara == adet) ödenen planlar; tutar, bu son taksitlerin toplamıdır.
    private static func installmentEnded(in previous: MonthlySchedule) -> MonthlyInsight.Detail? {
        let lastPayments = previous.entries.filter { entry in
            if case .installment(let number, let count) = entry.kind { return number == count }
            return false
        }
        guard !lastPayments.isEmpty else { return nil }
        let amount = lastPayments.reduce(Money.zero) { $0 + $1.amount }
        return .installmentEnded(titles: lastPayments.map(\.title), amount: amount)
    }
}
