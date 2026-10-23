import Foundation

/// One local reminder the app should schedule: the payments due on one day, at one fire time.
///
/// Same-day payments share a single reminder per ``Kind`` so the pending window is not wasted.
public struct PlannedReminder: Sendable, Hashable, Identifiable {
    /// When the reminder fires relative to the due day.
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        /// The day before the due day, at ``NotificationPlanner/fireHour``.
        case dayBefore
        /// On the due day, at ``NotificationPlanner/fireHour``.
        case dueDay
    }

    /// A deterministic id: `due-YYYY-MM-DD-today` for ``Kind/dueDay``,
    /// `due-YYYY-MM-DD-dayBefore` for ``Kind/dayBefore``; the date is the **due** date.
    public let id: String
    /// The moment the reminder fires; always after the planner's `now`.
    public let fireDate: Date
    /// Day before or due day.
    public let kind: Kind
    /// The day the covered payments are due.
    public let dueDate: Card.DueDate
    /// The notification title, e.g. `"Payment due today"`.
    public let title: String
    /// The notification body, e.g. `"Rent due today, ₺15.000,00"` or
    /// `"3 payments due tomorrow, ₺1.234,00 total"`.
    public let body: String
    /// The payments the reminder covers, in schedule order; never empty.
    public let entries: [MonthlySchedule.Entry]
    /// The exact sum of ``entries``.
    public let total: Money
}

/// Plans local payment reminders (pure; no side effects, no notification framework).
///
/// Each due day gets up to two reminders at ``fireHour``:00 — the day before and on the day —
/// in the given calendar's time zone (dates themselves are Gregorian, like ``YearMonth``).
/// Reminders at or before `now` are dropped. Only the nearest ``windowSize`` reminders are
/// kept, because iOS keeps at most ``maxPending`` pending local notifications; the rest are
/// planned again later (rolling window).
public enum NotificationPlanner {
    /// The most pending local notifications iOS keeps.
    public static let maxPending = 64
    /// The number of reminders planned: one slot under ``maxPending`` is kept spare.
    public static let windowSize = maxPending - 1
    /// The hour (0–23, local time) every reminder fires at.
    public static let fireHour = 9
    /// The months scanned when no lookahead is given (the current month included).
    public static let defaultLookaheadMonths = 3

    /// Plans the reminders for the payments due from `now`'s month over `lookaheadMonths` months.
    ///
    /// - Parameters:
    ///   - now: The current moment; reminders firing at or before it are dropped.
    ///   - calendar: Its time zone sets the local 09:00 and the current month.
    ///   - lookaheadMonths: The number of months scanned, starting with `now`'s month. Every
    ///     reminder fires within these months, and every payment due in them is planned.
    ///     One more month is also read, only for the day-before reminder of a payment due
    ///     on its 1st, which fires at 09:00 on the last day of the last scanned month. No
    ///     other reminder of that extra month is planned. Months after 9999-12 are skipped.
    ///     A negative value counts as `0`, and `0` plans nothing.
    ///   - kinds: The kinds planned (default: both). The extra month's day-before reminder is
    ///     planned only when ``PlannedReminder/Kind/dayBefore`` is requested; an empty set plans nothing.
    ///   - formatAmount: Formats an amount for the body (e.g. the app's lira formatter).
    /// - Returns: At most ``windowSize`` reminders, sorted by fire date, then id.
    public static func plan(
        now: Date,
        calendar: Calendar,
        cards: [Card],
        installments: [InstallmentItem],
        subscriptions: [SubscriptionItem],
        lookaheadMonths: Int = NotificationPlanner.defaultLookaheadMonths,
        kinds: Set<PlannedReminder.Kind> = [.dayBefore, .dueDay],
        formatAmount: (Money) -> String
    ) -> [PlannedReminder] {
        // Negatif değer sıfır sayılır; sıfır ay taranırsa plan boştur. Tür istenmezse de plan boştur.
        let scannedMonths = max(0, lookaheadMonths)
        guard scannedMonths > 0, !kinds.isEmpty else { return [] }
        // Tarihler YearMonth gibi Gregoryen; cihaz takviminden yalnızca saat dilimi alınır.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone

        let upcoming = UpcomingMonths(
            start: YearMonth(date: now, calendar: calendar),
            // Bir ay fazlası: sonraki ayın 1'inin gün öncesi hatırlatması taranan son günde çalar.
            // UpcomingMonths 9999-12 sonrasını zaten kırpar.
            count: scannedMonths + 1,
            cards: cards,
            installments: installments,
            subscriptions: subscriptions
        )

        var reminders: [PlannedReminder] = []
        for (index, schedule) in upcoming.schedules.enumerated() {
            let isSpillOver = index == scannedMonths
            for day in schedule.days {
                // Ek aydan yalnızca 1'inin gün öncesi alınır; böylece hiçbir hatırlatma
                // taranan ayların son gününden sonra çalmaz.
                if isSpillOver && day.day != 1 { continue }
                let dueDate = Card.DueDate(month: schedule.month, day: day.day)
                // Yalnızca istenen türler planlanır; ek ay yalnızca gün öncesi istenirse katkı verir.
                for kind in PlannedReminder.Kind.allCases where kinds.contains(kind) {
                    if isSpillOver && kind != .dayBefore { continue }
                    // Geçmişte (veya tam şimdi) çalacak hatırlatma kurulamaz; atlanır.
                    guard let fireDate = fireDate(of: kind, for: dueDate, in: gregorian),
                          fireDate > now else { continue }
                    reminders.append(PlannedReminder(
                        id: id(of: kind, for: dueDate),
                        fireDate: fireDate,
                        kind: kind,
                        dueDate: dueDate,
                        title: title(of: kind),
                        body: body(of: kind, entries: day.entries, total: day.total, formatAmount: formatAmount),
                        entries: day.entries,
                        total: day.total
                    ))
                }
            }
        }

        // Eşit zamanlarda id belirleyici olur; pencere en yakın windowSize hatırlatmayla sınırlanır.
        reminders.sort { lhs, rhs in
            lhs.fireDate != rhs.fireDate ? lhs.fireDate < rhs.fireDate : lhs.id < rhs.id
        }
        return Array(reminders.prefix(windowSize))
    }

    // Vade günü (veya bir önceki gün) yerel saatle 09:00. Gün 0, önceki ayın son gününe normalize edilir
    // (ör. 1 Ocak'ın önceki günü 31 Aralık).
    private static func fireDate(of kind: PlannedReminder.Kind, for dueDate: Card.DueDate, in calendar: Calendar) -> Date? {
        let offset = kind == .dayBefore ? -1 : 0
        let components = DateComponents(
            year: dueDate.month.year, month: dueDate.month.month, day: dueDate.day + offset,
            hour: fireHour, minute: 0, second: 0
        )
        return calendar.date(from: components)
    }

    // "due-2026-11-05-today" / "due-2026-11-05-dayBefore": vade tarihine bağlı, sabit ve sıralanabilir.
    private static func id(of kind: PlannedReminder.Kind, for dueDate: Card.DueDate) -> String {
        let suffix = kind == .dueDay ? "today" : "dayBefore"
        return "due-\(padded(dueDate.month.year, to: 4))-\(padded(dueDate.month.month, to: 2))-\(padded(dueDate.day, to: 2))-\(suffix)"
    }

    private static func padded(_ value: Int, to width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }

    private static func title(of kind: PlannedReminder.Kind) -> String {
        kind == .dueDay ? "Payment due today" : "Payment due tomorrow"
    }

    // Tek ödeme kendi adını söyler; birden fazlası sayı ve toplamla tek bildirimde toplanır.
    private static func body(
        of kind: PlannedReminder.Kind,
        entries: [MonthlySchedule.Entry],
        total: Money,
        formatAmount: (Money) -> String
    ) -> String {
        let when = kind == .dueDay ? "today" : "tomorrow"
        if entries.count == 1, let entry = entries.first {
            return "\(entry.title) due \(when), \(formatAmount(entry.amount))"
        }
        return "\(entries.count) payments due \(when), \(formatAmount(total)) total"
    }
}
