import Foundation

/// Spending figures derived from the same inputs as ``MonthlySchedule`` (ADR-0002 due-date rule).
///
/// Every figure is built from ``MonthlySchedule``, so totals match it exactly; items whose
/// card is not in the given cards are skipped like there. Pure domain: no UI or storage types.
public struct SpendingAnalytics: Sendable, Hashable {
    /// What is due in one month, split by kind.
    public struct MonthTotal: Sendable, Hashable {
        /// The month.
        public let month: YearMonth
        /// The exact sum of the installment payments due in ``month``.
        public let installments: Money
        /// The exact sum of the subscription charges due in ``month``.
        public let subscriptions: Money
        /// ``installments`` + ``subscriptions``; equals ``MonthlySchedule/total`` of the month.
        public let total: Money

        /// Creates a month's figures; ``total`` is always ``installments`` + ``subscriptions``.
        public init(month: YearMonth, installments: Money, subscriptions: Money) {
            self.month = month
            self.installments = installments
            self.subscriptions = subscriptions
            self.total = installments + subscriptions
        }
    }

    /// What one card (or no card) is due in one month.
    public struct CardShare: Sendable, Hashable {
        /// The card, or `nil` for subscriptions paid without a card (the `noCard` share).
        public let card: Card?
        /// The exact sum due in the month for this card.
        public let total: Money

        /// `true` for the share of payments that have no card.
        public var isNoCard: Bool { card == nil }

        /// Creates a share of `total` for `card` (`nil` for payments without a card).
        public init(card: Card?, total: Money) {
            self.card = card
            self.total = total
        }
    }

    private let cards: [Card]
    private let installments: [InstallmentItem]
    private let subscriptions: [SubscriptionItem]

    /// Builds analytics over the given cards and their items.
    public init(cards: [Card], installments: [InstallmentItem], subscriptions: [SubscriptionItem]) {
        self.cards = cards
        self.installments = installments
        self.subscriptions = subscriptions
    }

    private func schedule(for month: YearMonth) -> MonthlySchedule {
        MonthlySchedule(month: month, cards: cards, installments: installments, subscriptions: subscriptions)
    }

    /// The totals of `count` consecutive months starting at `start`, in order.
    ///
    /// Months without payments are kept with zero totals. `count <= 0` returns an empty array;
    /// months after the last supported month (9999-12) are left out instead of trapping.
    public func monthlyTotals(from start: YearMonth, count: Int) -> [MonthTotal] {
        guard count > 0 else { return [] }
        // Desteklenen son aydan sonrası temsil edilemez; `adding(months:)` çökmesin diye kırpılır.
        let last = YearMonth(year: YearMonth.supportedYears.upperBound, month: 12)!
        let available = start.months(until: last) + 1
        return (0..<min(count, available)).map { offset in
            let month = start.adding(months: offset)
            var installmentsSum = Money.zero
            var subscriptionsSum = Money.zero
            for entry in schedule(for: month).entries {
                switch entry.kind {
                case .installment: installmentsSum = installmentsSum + entry.amount
                case .subscription: subscriptionsSum = subscriptionsSum + entry.amount
                }
            }
            // Toplam, parçaların toplamıdır; yuvarlama kayması olamaz.
            return MonthTotal(month: month, installments: installmentsSum, subscriptions: subscriptionsSum)
        }
    }

    /// What each card is due in `month`, largest first; the shares sum exactly to the month total.
    ///
    /// Cards with nothing due are left out. Payments without a card form one `noCard` share
    /// (``CardShare/card`` is `nil`). Ties are ordered by card name (case-insensitive), then
    /// card id; the `noCard` share comes after cards with the same total.
    public func cardBreakdown(in month: YearMonth) -> [CardShare] {
        let entries = schedule(for: month).entries
        // Aynı id'li kartlarda ilki geçerli sayılır (MonthlySchedule ile aynı).
        let cardsByID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var totals: [Card.ID: Money] = [:]
        var noCardTotal: Money?
        for entry in entries {
            if let cardID = entry.cardID {
                totals[cardID, default: .zero] = totals[cardID, default: .zero] + entry.amount
            } else {
                noCardTotal = (noCardTotal ?? .zero) + entry.amount
            }
        }
        var shares = totals.compactMap { id, total in
            cardsByID[id].map { CardShare(card: $0, total: total) }
        }
        shares.sort { lhs, rhs in
            if lhs.total != rhs.total { return lhs.total > rhs.total }
            let (a, b) = (lhs.card!, rhs.card!)
            let byName = a.name.caseInsensitiveCompare(b.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return a.id.uuidString < b.id.uuidString
        }
        if let noCardTotal {
            // `noCard` payı, eşit toplamlı kartlardan sonra gelir.
            let share = CardShare(card: nil, total: noCardTotal)
            let index = shares.firstIndex { $0.total < noCardTotal } ?? shares.endIndex
            shares.insert(share, at: index)
        }
        return shares
    }

    /// The last month with an installment payment due ("debt-free month" for installments),
    /// or `nil` when there are no installments (items with an unknown card do not count;
    /// card-less items do).
    public var lastPaymentMonth: YearMonth? {
        let knownCardIDs = Set(cards.map(\.id))
        // Kartsız taksit her zaman sayılır; kartlıysa kart bilinmeli.
        let known = installments.filter { $0.cardID.map(knownCardIDs.contains) ?? true }
        // Vade, ekstre ayında veya sonraki ayda olur; son vade en geç son ekstre ayı + 1'dedir.
        guard let lastStatement = known.map(\.plan.lastMonth).max() else { return nil }
        // 9999-12'den sonrası temsil edilemez; `adding(months:)` çökmesin diye elenir.
        let end = YearMonth(year: YearMonth.supportedYears.upperBound, month: 12)!
        let candidates = lastStatement == end ? [lastStatement] : [lastStatement.adding(months: 1), lastStatement]
        return candidates.first { month in
            schedule(for: month).entries.contains {
                if case .installment = $0.kind { return true }
                return false
            }
        }
    }
}
