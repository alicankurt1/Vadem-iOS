import Foundation

/// The schedules of consecutive months starting at ``start``: "what's coming?".
///
/// Each month is a full ``MonthlySchedule``, so its total is exactly ``MonthlySchedule/total``.
/// Months with no payments are kept (with a zero total), never omitted.
public struct UpcomingMonths: Sendable, Hashable {
    /// The number of months built when no count is given.
    public static let defaultCount = 6

    /// The first month.
    public let start: YearMonth
    /// One schedule per month, in order: `start`, `start + 1`, …
    public let schedules: [MonthlySchedule]

    /// Builds the schedules of `count` months from `start` forward.
    ///
    /// Months after the last supported month (9999-12) are left out instead of trapping.
    /// - Precondition: `count >= 0`.
    public init(
        start: YearMonth,
        count: Int = UpcomingMonths.defaultCount,
        cards: [Card],
        installments: [InstallmentItem],
        subscriptions: [SubscriptionItem]
    ) {
        precondition(count >= 0, "UpcomingMonths count must not be negative: \(count)")
        // Desteklenen son aydan sonrası temsil edilemez; `adding(months:)` çökmesin diye kırpılır.
        let last = YearMonth(year: YearMonth.supportedYears.upperBound, month: 12)!
        let available = start.months(until: last) + 1
        self.start = start
        self.schedules = (0..<min(count, available)).map { offset in
            MonthlySchedule(
                month: start.adding(months: offset),
                cards: cards,
                installments: installments,
                subscriptions: subscriptions
            )
        }
    }

    /// The months, in order.
    public var months: [YearMonth] {
        schedules.map(\.month)
    }
}
