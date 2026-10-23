import Foundation
import VademCore

/// Builds the home-screen widget's timeline from the saved payments, via ``PaymentSummary``.
///
/// Free of WidgetKit so it is testable on macOS; the widget extension only maps the result to a
/// `Timeline`. Entries cover now and each local midnight of the next ``daysAhead`` days, so
/// "Today" / "Tomorrow" / "in N days" and the remaining amount stay right without waking the
/// widget process. Never throws: a repository error yields one ``Content/unavailable`` entry.
@MainActor
public struct WidgetTimelineBuilder {
    /// What one entry shows.
    public enum Content: Sendable, Hashable {
        /// The summary of the entry's day; something is due this month or later.
        case summary(PaymentSummary)
        /// Nothing is due this month and nothing is upcoming.
        case empty
        /// The payments could not be loaded.
        case unavailable
    }

    /// One moment of the timeline.
    public struct Entry: Sendable, Hashable {
        /// When the entry becomes current.
        public let date: Date
        /// What the widget shows from ``date`` on.
        public let content: Content

        /// Creates an entry.
        public init(date: Date, content: Content) {
            self.date = date
            self.content = content
        }
    }

    /// The entries plus the moment to ask for a new timeline.
    public struct Result: Sendable, Hashable {
        /// Sorted by date; the first one is at `now`.
        public let entries: [Entry]
        /// The midnight after the last entry, or `now` + ``WidgetTimelineBuilder/retryInterval``
        /// when the payments could not be loaded.
        public let reloadDate: Date
    }

    /// The local midnights after `now` that get their own entry.
    public static let daysAhead = 3
    /// How long to wait before retrying after a repository error: one hour.
    public static let retryInterval: TimeInterval = 60 * 60

    private let repository: any PaymentRepository
    private let calendar: Calendar

    /// Creates a builder; only `calendar`'s time zone is used (days are Gregorian, like ``PaymentSummary``).
    public init(repository: any PaymentRepository, calendar: Calendar) {
        self.repository = repository
        // PaymentSummary gibi: takvimden yalnızca saat dilimi alınır, günler Gregoryen.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        self.calendar = gregorian
    }

    /// The timeline starting at `now`.
    public func timeline(now: Date) -> Result {
        let cards: [Card]
        let installments: [InstallmentItem]
        let subscriptions: [SubscriptionItem]
        do {
            cards = try repository.cards()
            installments = try repository.installments()
            subscriptions = try repository.subscriptions()
        } catch {
            // Depo okunamazsa çökmek yerine tek bir "açılamadı" girdisi; bir saat sonra yeniden denenir.
            return unavailable(now: now)
        }

        // Gece yarıları startOfDay + gün ekleme ile bulunur: yaz saati günleri 23 ya da 25 saat sürse de
        // her girdi yerel gece yarısına düşer (sabit 86 400 saniye eklenmez).
        let today = calendar.startOfDay(for: now)
        var dates = [now]
        for offset in 1...(Self.daysAhead + 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else {
                return unavailable(now: now)
            }
            dates.append(calendar.startOfDay(for: day))
        }
        // Son tarih girdi değil, yeni zaman çizelgesinin isteneceği an.
        let reloadDate = dates.removeLast()

        let entries = dates.map { date in
            let summary = PaymentSummary(
                now: date,
                calendar: calendar,
                cards: cards,
                installments: installments,
                subscriptions: subscriptions
            )
            let isEmpty = summary.monthTotal.isZero && summary.next.isEmpty
            return Entry(date: date, content: isEmpty ? .empty : .summary(summary))
        }
        return Result(entries: entries, reloadDate: reloadDate)
    }

    private func unavailable(now: Date) -> Result {
        Result(
            entries: [Entry(date: now, content: .unavailable)],
            reloadDate: now.addingTimeInterval(Self.retryInterval)
        )
    }
}
