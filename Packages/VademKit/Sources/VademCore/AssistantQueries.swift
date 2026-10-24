import Foundation

/// Salt okunur sorgular: yerel asistanın modele verdiği tek veri kaynağı.
///
/// Değer tiplerinden kurulur, depo veya yan etki yoktur. Tüm sayılar
/// ``MonthlySchedule``, ``PaymentSummary`` ve ``SpendingAnalytics`` üzerinden gelir (yeni
/// para hesabı yok); kullanıcı metinleri ``PromptSafeText`` ile temizlenir.
public struct AssistantQueries: Sendable {
    /// The most payments ``payments(in:)`` returns.
    public static let maxPayments = 20

    private let cards: [Card]
    private let installments: [InstallmentItem]
    private let subscriptions: [SubscriptionItem]

    /// Builds queries over the given cards and their items.
    public init(cards: [Card], installments: [InstallmentItem], subscriptions: [SubscriptionItem]) {
        self.cards = cards
        self.installments = installments
        self.subscriptions = subscriptions
    }

    private func schedule(for month: YearMonth) -> MonthlySchedule {
        MonthlySchedule(month: month, cards: cards, installments: installments, subscriptions: subscriptions)
    }

    // Aynı id'li kartlarda ilki geçerli sayılır (MonthlySchedule ile aynı).
    private var cardNames: [Card.ID: String] {
        Dictionary(cards.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// What is due in `month`: the exact total and the number of payments (zero when nothing is due).
    public func monthTotal(_ month: YearMonth) -> AssistantMonthTotal {
        let schedule = schedule(for: month)
        return AssistantMonthTotal(
            month: AssistantPayment.string(of: month),
            total: AssistantAmount(schedule.total),
            entryCount: schedule.entries.count
        )
    }

    /// The payments due in `month`, in ``MonthlySchedule`` order, at most ``maxPayments``.
    public func payments(in month: YearMonth) -> AssistantPayments {
        let entries = schedule(for: month).entries
        let names = cardNames
        return AssistantPayments(
            month: AssistantPayment.string(of: month),
            payments: entries.prefix(AssistantQueries.maxPayments).map {
                AssistantPayment(entry: $0, cardNames: names)
            },
            totalCount: entries.count
        )
    }

    /// The next payment due on or after the day of `date` in `calendar`'s time zone, or `nil`.
    ///
    /// Looks as far ahead as ``PaymentSummary/lookaheadMonths``.
    public func nextPayment(after date: Date, calendar: Calendar = .current) -> AssistantNextPayment? {
        let summary = PaymentSummary(
            now: date, calendar: calendar,
            cards: cards, installments: installments, subscriptions: subscriptions, limit: 1
        )
        guard let next = summary.next.first else { return nil }
        // Kart adı ve tür özetten gelmez; aynı ayın takviminden kalem ve gün ile bulunur.
        let entries = schedule(for: next.dueDate.month).entries
        // Girdi her zaman bulunur (özet aynı takvimden üretilir); nil dalı ulaşılamaz.
        guard let entry = entries.first(where: { $0.itemID == next.itemID && $0.dueDate == next.dueDate && $0.amount == next.amount })
        else { return nil }
        return AssistantNextPayment(
            payment: AssistantPayment(entry: entry, cardNames: cardNames),
            daysUntil: next.daysUntil
        )
    }

    /// What the card named `name` is due in `month`.
    ///
    /// The match ignores case and surrounding whitespace; if several cards share the name their
    /// payments are added up. An unknown name returns ``AssistantCardResult/notFound(requestedName:)``.
    public func cardTotal(cardNamed name: String, in month: YearMonth) -> AssistantCardResult {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Model kart adını yalnızca temizlenmiş/kısaltılmış haliyle görür; o hal de eşleşir.
        let safeWanted = PromptSafeText(name).value
        let matches = cards.filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(wanted) == .orderedSame
                || PromptSafeText($0.name).value.caseInsensitiveCompare(safeWanted) == .orderedSame
        }
        guard let first = matches.first else {
            return .notFound(requestedName: PromptSafeText(name))
        }
        let schedule = schedule(for: month)
        let ids = Set(matches.map(\.id))
        let total = matches.reduce(Money.zero) { $0 + schedule.total(for: $1.id) }
        return .total(AssistantCardTotal(
            cardName: PromptSafeText(first.name),
            month: AssistantPayment.string(of: month),
            total: AssistantAmount(total),
            entryCount: schedule.entries.filter { $0.cardID.map(ids.contains) ?? false }.count
        ))
    }

    /// The last month with an installment payment, or `month == nil` when there are no installments.
    public var debtFreeMonth: AssistantDebtFreeMonth {
        let analytics = SpendingAnalytics(cards: cards, installments: installments, subscriptions: subscriptions)
        return AssistantDebtFreeMonth(month: analytics.lastPaymentMonth.map(AssistantPayment.string(of:)))
    }
}
