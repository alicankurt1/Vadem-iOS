import Foundation
import Observation
import VademCore

/// Drives the Home screen: the payments due in the selected month, built with ``MonthlySchedule``.
///
/// "Today" is injected (`today` + `calendar`), never read from the clock, so results are deterministic.
/// Data is loaded on init; call ``reload()`` after the repository changes.
@MainActor
@Observable
public final class HomeViewModel {
    /// What the screen shows.
    public enum State: Sendable, Hashable {
        /// At least one payment is due in ``HomeViewModel/month``.
        case loaded
        /// Nothing is due in ``HomeViewModel/month``.
        case empty
        /// The repository failed; `message` is shown to the user.
        case error(message: String)
    }

    /// The subtotal of one card in the selected month.
    public struct CardSubtotal: Sendable, Hashable, Identifiable {
        /// The card's id.
        public let id: Card.ID
        /// The card's display name.
        public let name: String
        /// The exact sum of the card's payments in the month.
        public let amount: Money
    }

    /// One payment row, ready to display.
    public struct Row: Sendable, Hashable, Identifiable {
        /// Unique within the month (an item can have more than one payment in a month).
        public let id: String
        /// The schedule entry this row shows.
        public let entry: MonthlySchedule.Entry
        /// The item's title.
        public let title: String
        /// The card's name, or ``HomeViewModel/noCardText`` for a payment without a card.
        public let cardText: String
        /// `"3/12"` for installment payment 3 of 12; `nil` for a subscription.
        public let installmentText: String?
        /// The amount due.
        public let amount: Money
        /// The due date as `"15 October"`.
        public let dueText: String
        /// How soon the payment is due, relative to the injected today.
        public let chipKind: DueChip.Kind
        /// The chip's text, e.g. `"Overdue"`, `"Today"`, `"In 3 days"`, `"Later"`.
        public let chipText: String
        /// The whole row as one VoiceOver label:
        /// `"Netflix, 249,99 Türk lirası, due 15 October, Everyday card, In 3 days"`.
        public let accessibilityLabel: String
    }

    /// One month of the upcoming strip, ready to display.
    public struct MonthSummary: Sendable, Hashable, Identifiable {
        /// The month; unique within ``HomeViewModel/upcoming``.
        public var id: YearMonth { month }
        /// The month this summary covers.
        public let month: YearMonth
        /// The month as `"November 2026"`.
        public let title: String
        /// The month's ``MonthlySchedule/total``; zero when nothing is due.
        public let total: Money
        /// `true` for the selected month (``HomeViewModel/month``).
        public let isSelected: Bool
        /// The chip as one VoiceOver label: `"November 2026, 1.249,98 Türk lirası"`.
        public let accessibilityLabel: String
    }

    /// The text shown for a payment that is not charged to a card.
    public nonisolated static let noCardText = "No card"
    /// The message of the ``State/error(message:)`` state.
    public nonisolated static let loadErrorMessage = "Your payments could not be loaded."
    /// A payment due within this many days after today is ``DueChip/Kind/soon``.
    public nonisolated static let soonDays = 3

    /// The selected month.
    public private(set) var month: YearMonth
    /// The current state.
    public private(set) var state: State = .empty
    /// The schedule of ``month``, or `nil` after a repository error.
    public private(set) var schedule: MonthlySchedule?
    /// The total due in ``month``; zero when empty or after an error.
    public private(set) var total: Money = .zero
    /// Subtotals of the cards with payments in ``month``, in the repository's card order.
    public private(set) var cardSubtotals: [CardSubtotal] = []
    /// The payments of ``month``, in schedule order.
    public private(set) var rows: [Row] = []
    /// ``UpcomingMonths/defaultCount`` consecutive months with their totals.
    ///
    /// Starts at the current month while the selected month is one of them, otherwise at the
    /// selected month, so the selected month is always in the strip. Empty after a repository error.
    public private(set) var upcoming: [MonthSummary] = []

    @ObservationIgnored private let repository: any PaymentRepository
    // Enjekte edilen bugün: ay ve gün (Card.DueDate dışarıdan kurulamaz).
    @ObservationIgnored private var todayMonth: YearMonth
    @ObservationIgnored private var todayDay: Int
    @ObservationIgnored private let calendar: Calendar

    /// Creates the view model for the month that contains `today` in `calendar`'s time zone, and loads it.
    public init(repository: any PaymentRepository, today: Date, calendar: Calendar) {
        self.repository = repository
        // YearMonth gibi: sadece saat dilimi alınır, gün Gregoryen takvimle hesaplanır.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        self.calendar = gregorian
        let month = YearMonth(date: today, calendar: calendar)
        self.month = month
        self.todayMonth = month
        self.todayDay = gregorian.component(.day, from: today)
        reload()
    }

    /// The selected month as `"October 2026"`.
    public var monthTitle: String {
        Self.title(of: month)
    }

    /// Selects `month` (e.g. a tapped chip of ``upcoming``) and reloads.
    public func select(month: YearMonth) {
        self.month = month
        reload()
    }

    /// Selects the previous month and reloads.
    public func showPreviousMonth() {
        month = month.adding(months: -1)
        reload()
    }

    /// Selects the next month and reloads.
    public func showNextMonth() {
        month = month.adding(months: 1)
        reload()
    }

    /// Moves "today" to `date` (e.g. when the app becomes active after midnight) and reloads.
    ///
    /// If the selected month was the old current month, the new current month is selected;
    /// a month the user navigated to is kept.
    public func updateToday(_ date: Date) {
        let newMonth = YearMonth(date: date, calendar: calendar)
        // Kullanıcı başka aya geçmediyse seçim yeni "bu ay"ı izler.
        if month == todayMonth {
            month = newMonth
        }
        todayMonth = newMonth
        todayDay = calendar.component(.day, from: date)
        reload()
    }

    /// Loads the selected month from the repository; a thrown error becomes ``State/error(message:)``.
    public func reload() {
        do {
            let cards = try repository.cards()
            let installments = try repository.installments()
            let subscriptions = try repository.subscriptions()
            let schedule = MonthlySchedule(
                month: month, cards: cards, installments: installments, subscriptions: subscriptions
            )
            let upcomingMonths = UpcomingMonths(
                start: upcomingStart, cards: cards, installments: installments, subscriptions: subscriptions
            )
            apply(schedule, cards: cards)
            upcoming = upcomingMonths.schedules.map(makeSummary)
        } catch {
            // Hata sessizce boş liste olmaz; ekranda hata durumu gösterilir.
            schedule = nil
            total = .zero
            cardSubtotals = []
            rows = []
            upcoming = []
            state = .error(message: Self.loadErrorMessage)
        }
    }

    /// The chip kind of a payment due on `dueDate`, relative to the injected today.
    public func chipKind(for dueDate: Card.DueDate) -> DueChip.Kind {
        let days = daysFromToday(to: dueDate)
        if days < 0 { return .overdue }
        if days == 0 { return .today }
        if days <= Self.soonDays { return .soon }
        return .later
    }

    private func apply(_ schedule: MonthlySchedule, cards: [Card]) {
        let namesByID = Dictionary(cards.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let usedCardIDs = Set(schedule.entries.compactMap(\.cardID))
        // Aynı id'li kartlar tek alt toplam olarak gösterilir.
        var seen = Set<Card.ID>()
        cardSubtotals = cards.compactMap { card in
            guard usedCardIDs.contains(card.id), seen.insert(card.id).inserted else { return nil }
            return CardSubtotal(id: card.id, name: card.name, amount: schedule.total(for: card.id))
        }
        rows = schedule.entries.enumerated().map { index, entry in
            makeRow(entry, index: index, cardName: entry.cardID.flatMap { namesByID[$0] })
        }
        self.schedule = schedule
        total = schedule.total
        state = schedule.entries.isEmpty ? .empty : .loaded
    }

    // Şerit bu ayın penceresindeyse bu aydan, değilse seçili aydan başlar; seçili ay hep görünür.
    private var upcomingStart: YearMonth {
        let offset = todayMonth.months(until: month)
        return (0..<UpcomingMonths.defaultCount).contains(offset) ? todayMonth : month
    }

    private func makeSummary(_ schedule: MonthlySchedule) -> MonthSummary {
        let title = Self.title(of: schedule.month)
        return MonthSummary(
            month: schedule.month,
            title: title,
            total: schedule.total,
            isSelected: schedule.month == month,
            // Satırlarla aynı: "₺" yerine okunabilir tutar.
            accessibilityLabel: "\(title), \(AmountText.spokenLabel(schedule.total))"
        )
    }

    private func makeRow(_ entry: MonthlySchedule.Entry, index: Int, cardName: String?) -> Row {
        let cardText = cardName ?? Self.noCardText
        let installmentText: String?
        let spokenInstallment: String?
        switch entry.kind {
        case .installment(let number, let count):
            installmentText = "\(number)/\(count)"
            spokenInstallment = "installment \(number) of \(count)"
        case .subscription:
            installmentText = nil
            spokenInstallment = nil
        }
        let kind = chipKind(for: entry.dueDate)
        let chipText = chipText(for: kind, dueDate: entry.dueDate)
        let dueText = "\(entry.dueDate.day) \(Self.monthNames[entry.dueDate.month.month - 1])"
        // VoiceOver satırı tek öğe olarak okur; "₺" yerine okunabilir tutar kullanılır.
        let parts = [entry.title, spokenInstallment, AmountText.spokenLabel(entry.amount),
                     "due \(dueText)", cardText, chipText].compactMap { $0 }
        return Row(
            id: "\(index)-\(entry.itemID.uuidString)",
            entry: entry,
            title: entry.title,
            cardText: cardText,
            installmentText: installmentText,
            amount: entry.amount,
            dueText: dueText,
            chipKind: kind,
            chipText: chipText,
            accessibilityLabel: parts.joined(separator: ", ")
        )
    }

    private func chipText(for kind: DueChip.Kind, dueDate: Card.DueDate) -> String {
        switch kind {
        case .overdue: return "Overdue"
        case .today: return "Today"
        case .soon:
            let days = daysFromToday(to: dueDate)
            return days == 1 ? "Tomorrow" : "In \(days) days"
        case .later: return "Later"
        }
    }

    // Bugünden vade gününe gün farkı (geçmiş negatif). Öğlen saati yaz saati geçişlerinden etkilenmez.
    private func daysFromToday(to dueDate: Card.DueDate) -> Int {
        guard let start = noon(of: todayMonth, day: todayDay),
              let end = noon(of: dueDate.month, day: dueDate.day) else { return 0 }
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    private func noon(of month: YearMonth, day: Int) -> Date? {
        calendar.date(from: DateComponents(year: month.year, month: month.month, day: day, hour: 12))
    }

    private nonisolated static func title(of month: YearMonth) -> String {
        "\(monthNames[month.month - 1]) \(month.year)"
    }

    // Ay adları sabit (İngilizce); cihaz diline bağlı değil, ekran metinleriyle uyumlu.
    private nonisolated static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]
}
