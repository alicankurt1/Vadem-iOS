import Foundation

/// "How much do I pay this month, and what is next?": the summary the widget and Siri read.
///
/// Pure and deterministic: built from `now`, a calendar (only its time zone is used; dates are
/// Gregorian, like ``YearMonth``) and the user's items, via ``MonthlySchedule`` and ``UpcomingMonths``.
public struct PaymentSummary: Sendable, Hashable {
    /// One upcoming payment. Same-day payments are separate rows.
    public struct Upcoming: Sendable, Hashable {
        /// The id of the ``InstallmentItem``, ``SubscriptionItem`` or ``OneTimePaymentItem``.
        public let itemID: UUID
        /// The item's title.
        public let title: String
        /// The amount due.
        public let amount: Money
        /// The day the payment is due.
        public let dueDate: Card.DueDate
        /// Days from today to ``dueDate``: `0` = today, `1` = tomorrow; never negative.
        public let daysUntil: Int
    }

    /// The number of upcoming payments listed when no limit is given.
    public static let defaultLimit = 3
    /// The months scanned for ``next``, the current month included (same as the planner).
    public static let lookaheadMonths = NotificationPlanner.defaultLookaheadMonths

    /// The month of `now`.
    public let month: YearMonth
    /// The exact sum of everything due in ``month``.
    public let monthTotal: Money
    /// The exact sum of the payments due today or later in ``month``.
    public let remaining: Money
    /// The number of payments due today or later in ``month``.
    public let remainingCount: Int
    /// The nearest payments due today or later (at most the given limit), sorted by due date,
    /// then title (case-insensitive), then item id; may reach into the following months.
    public let next: [Upcoming]

    /// Builds the summary for `now`.
    ///
    /// - Parameters:
    ///   - now: The current moment; its day in `calendar`'s time zone is "today".
    ///   - calendar: Only its time zone is used.
    ///   - limit: The most rows in ``next``; a negative value counts as `0`.
    public init(
        now: Date,
        calendar: Calendar,
        cards: [Card],
        installments: [InstallmentItem],
        subscriptions: [SubscriptionItem],
        oneTimePayments: [OneTimePaymentItem] = [],
        limit: Int = PaymentSummary.defaultLimit
    ) {
        // Bugün YearMonth gibi Gregoryen hesaplanır; cihaz takviminden yalnızca saat dilimi alınır.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let month = YearMonth(date: now, calendar: calendar)
        let today = gregorian.component(.day, from: now)

        let upcoming = UpcomingMonths(
            start: month,
            count: PaymentSummary.lookaheadMonths,
            cards: cards,
            installments: installments,
            subscriptions: subscriptions,
            oneTimePayments: oneTimePayments
        )
        // UpcomingMonths ilk ayı her zaman içerir (count > 0 ve başlangıç desteklenen aralıkta).
        let current = upcoming.schedules[0]
        // Bugün vadesi gelen ödeme kalan sayılır; ayın geçmiş günleri sayılmaz.
        let remainingEntries = current.entries.filter { $0.dueDate.day >= today }

        // Aylar sırayla, her ayın girdileri zaten vade günü, başlık, id sırasında;
        // art arda eklemek genel sırayı korur. Geçmiş günler yalnızca ilk ayda olabilir.
        var next: [Upcoming] = []
        let maxCount = max(0, limit)
        scan: for schedule in upcoming.schedules {
            for entry in schedule.entries {
                guard next.count < maxCount else { break scan }
                let days = PaymentSummary.days(from: month, day: today, to: entry.dueDate)
                guard days >= 0 else { continue }
                next.append(Upcoming(
                    itemID: entry.itemID, title: entry.title, amount: entry.amount,
                    dueDate: entry.dueDate, daysUntil: days
                ))
            }
        }

        self.month = month
        self.monthTotal = current.total
        self.remaining = remainingEntries.reduce(Money.zero) { $0 + $1.amount }
        self.remainingCount = remainingEntries.count
        self.next = next
    }

    /// The month total as a sentence, e.g. `"You pay <amount> in October 2026, <amount> still to go."`.
    ///
    /// The "still to go" part is left out when ``remaining`` is zero or equals ``monthTotal``;
    /// a month with nothing due reads `"Nothing is due in October 2026."`. Locale-independent.
    /// - Parameter spokenAmount: Speaks an amount (e.g. the app's spoken lira label).
    public func spokenMonthTotal(spokenAmount: (Money) -> String) -> String {
        let monthText = "\(PaymentSummary.monthNames[month.month - 1]) \(month.year)"
        guard !monthTotal.isZero else { return "Nothing is due in \(monthText)." }
        let total = "You pay \(spokenAmount(monthTotal)) in \(monthText)"
        if remaining.isZero || remaining == monthTotal { return total + "." }
        return total + ", \(spokenAmount(remaining)) still to go."
    }

    /// The first of ``next`` as a sentence, e.g. `"Next: Rent, <amount>, today."`.
    ///
    /// The day reads `today`, `tomorrow`, `in N days` (2–6) or `on 3 November` (7 or more days);
    /// `"No upcoming payments."` when ``next`` is empty. Locale-independent.
    /// - Parameter spokenAmount: Speaks an amount (e.g. the app's spoken lira label).
    public func spokenNextPayment(spokenAmount: (Money) -> String) -> String {
        guard let first = next.first else { return "No upcoming payments." }
        let when: String
        switch first.daysUntil {
        case 0: when = "today"
        case 1: when = "tomorrow"
        case 2..<7: when = "in \(first.daysUntil) days"
        default: when = "on \(first.dueDate.day) \(PaymentSummary.monthNames[first.dueDate.month.month - 1])"
        }
        return "Next: \(first.title), \(spokenAmount(first.amount)), \(when)."
    }

    // Bugünden vade tarihine gün farkı; yalnızca YearMonth gün sayılarıyla (artık yıllar dahil),
    // Foundation takvimine ve saat dilimi geçişlerine bağlı değil. Vade önceki aydaysa negatif olur.
    private static func days(from month: YearMonth, day today: Int, to due: Card.DueDate) -> Int {
        let monthsAhead = month.months(until: due.month)
        guard monthsAhead >= 0 else { return -1 }
        let skipped = (0..<monthsAhead).reduce(0) { $0 + month.adding(months: $1).numberOfDays }
        return skipped + due.day - today
    }

    // Dil ayarından bağımsız İngilizce ay adları (Siri metni sabit kalsın diye).
    private static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]
}
