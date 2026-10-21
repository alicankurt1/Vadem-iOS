import Foundation

/// The payments due in one month (ADR-0002): a payment belongs to the month its
/// **due date** falls in, not the month it was charged or its statement was cut.
///
/// - Installment payment `n` is on the statement cut in its month; it is due on
///   ``Card/dueDate(forStatementIn:)`` of that month.
/// - A subscription on a card charged on or before the card's statement day is on that
///   month's statement, otherwise on the next month's; it is due on that statement's due date.
/// - A subscription without a card is due on its charge date.
///
/// Items whose card is not in the given cards are skipped.
public struct MonthlySchedule: Sendable, Hashable {
    /// One payment due in ``MonthlySchedule/month``.
    public struct Entry: Sendable, Hashable {
        /// What kind of item the payment comes from.
        public enum Kind: Sendable, Hashable {
            /// Payment `number` of an installment plan with `count` payments.
            case installment(number: Int, count: Int)
            /// A subscription charge.
            case subscription
        }

        /// The id of the ``InstallmentItem`` or ``SubscriptionItem``.
        public let itemID: UUID
        /// The item's title.
        public let title: String
        /// Installment number/count, or subscription.
        public let kind: Kind
        /// The card the payment is charged to, or `nil` for a subscription paid another way.
        public let cardID: Card.ID?
        /// The amount due.
        public let amount: Money
        /// The day the payment is due; its month is always ``MonthlySchedule/month``.
        public let dueDate: Card.DueDate
    }

    /// The month the schedule covers.
    public let month: YearMonth
    /// Every payment due in ``month``, ordered by due day, then title
    /// (case-insensitive), then item id.
    public let entries: [Entry]
    /// The exact sum of ``entries``.
    public let total: Money

    /// Builds the schedule of payments due in `month`.
    public init(month: YearMonth, cards: [Card], installments: [InstallmentItem], subscriptions: [SubscriptionItem]) {
        // Aynı id'li kartlar varsa ilki geçerli sayılır (çökme yerine).
        let cardsByID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var entries: [Entry] = []

        for item in installments {
            // Kartı bilinmeyen taksit atlanır.
            guard let card = cardsByID[item.cardID] else { continue }
            for payment in item.plan.payments {
                // Ekstre ayı M-1 veya M olan taksitlerin vadesi M'de olabilir; diğerleri olamaz.
                guard (0...1).contains(payment.month.months(until: month)),
                      let due = MonthlySchedule.dueDate(of: card, forStatementIn: payment.month),
                      due.month == month else { continue }
                entries.append(Entry(
                    itemID: item.id, title: item.title,
                    kind: .installment(number: payment.number, count: item.plan.count),
                    cardID: card.id, amount: payment.amount, dueDate: due
                ))
            }
        }

        for item in subscriptions {
            let subscription = item.subscription
            guard let cardID = item.cardID else {
                // Kartsız abonelik çekim gününde ödenir.
                if let day = subscription.chargeDay(in: month) {
                    entries.append(Entry(
                        itemID: item.id, title: item.title, kind: .subscription, cardID: nil,
                        amount: subscription.amount(in: month), dueDate: Card.DueDate(month: month, day: day)
                    ))
                }
                continue
            }
            // Kartı bilinmeyen abonelik atlanır.
            guard let card = cardsByID[cardID] else { continue }
            // M-2'deki çekim M-1 ekstresine girip M'de ödenebilir; bu yüzden M-2...M taranır.
            for offset in -2...0 {
                guard let chargeMonth = MonthlySchedule.month(month, shiftedBy: offset),
                      let chargeDay = subscription.chargeDay(in: chargeMonth) else { continue }
                // Ekstre gününe denk gelen çekim o ekstreye dahildir.
                // chargeMonth < month olduğunda +1 güvenli; chargeMonth == month ise sonraki ay
                // ekstresinin vadesi en erken M+1'dedir, o yüzden atlanır.
                let statementMonth: YearMonth
                if chargeDay <= card.statementDay(in: chargeMonth) {
                    statementMonth = chargeMonth
                } else if chargeMonth < month {
                    statementMonth = chargeMonth.adding(months: 1)
                } else {
                    continue
                }
                guard let due = MonthlySchedule.dueDate(of: card, forStatementIn: statementMonth),
                      due.month == month else { continue }
                entries.append(Entry(
                    itemID: item.id, title: item.title, kind: .subscription, cardID: card.id,
                    amount: subscription.amount(in: chargeMonth), dueDate: due
                ))
            }
        }

        // Sıralama: vade günü, başlık (büyük/küçük harf duyarsız), id; aynı kalemin
        // iki taksiti aynı güne düşerse taksit numarası belirleyici olur.
        entries.sort { lhs, rhs in
            if lhs.dueDate.day != rhs.dueDate.day { return lhs.dueDate.day < rhs.dueDate.day }
            let byTitle = lhs.title.caseInsensitiveCompare(rhs.title)
            if byTitle != .orderedSame { return byTitle == .orderedAscending }
            if lhs.itemID != rhs.itemID { return lhs.itemID.uuidString < rhs.itemID.uuidString }
            return lhs.kind.sortNumber < rhs.kind.sortNumber
        }

        self.month = month
        self.entries = entries
        self.total = MonthlySchedule.sum(entries)
    }

    /// The exact sum of the entries charged to `cardID`.
    public func total(for cardID: Card.ID) -> Money {
        MonthlySchedule.sum(entries.filter { $0.cardID == cardID })
    }

    private static func sum(_ entries: [Entry]) -> Money {
        entries.reduce(Money.zero) { $0 + $1.amount }
    }

    // `adding(months:)` aralık dışında çöker; desteklenen aralık dışındaki ay için nil döner.
    private static func month(_ month: YearMonth, shiftedBy offset: Int) -> YearMonth? {
        let first = YearMonth(year: YearMonth.supportedYears.lowerBound, month: 1)!
        guard first.months(until: month) + offset >= 0 else { return nil }
        return month.adding(months: offset)
    }

    // Son desteklenen ayın (9999-12) ekstresinin vadesi sonraki yıla düşüyorsa temsil edilemez;
    // `dueDate(forStatementIn:)` çökmesin diye nil döner. Aralık 31 gün olduğundan kırpma yoktur.
    private static func dueDate(of card: Card, forStatementIn statementMonth: YearMonth) -> Card.DueDate? {
        let last = YearMonth(year: YearMonth.supportedYears.upperBound, month: 12)!
        if statementMonth == last, card.dueDay <= card.statementDay(in: statementMonth) { return nil }
        return card.dueDate(forStatementIn: statementMonth)
    }
}

private extension MonthlySchedule.Entry.Kind {
    // Son eşitlik kırıcı: taksit numarası (abonelikler 0).
    var sortNumber: Int {
        switch self {
        case .installment(let number, _): return number
        case .subscription: return 0
        }
    }
}
