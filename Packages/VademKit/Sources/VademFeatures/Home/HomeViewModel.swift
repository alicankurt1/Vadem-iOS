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

    /// One cell of the month grid: a leading blank (``day`` is `nil`) or a day of the month.
    public struct CalendarDay: Sendable, Hashable, Identifiable {
        /// The cell's position in the grid, from 0; unique within ``HomeViewModel/calendarDays``.
        public let id: Int
        /// The day of the month, or `nil` for a blank before the 1st.
        public let day: Int?
        /// The exact sum of the day's payments; zero for a blank or a day without payments.
        public let total: Money
        /// The number of payments due that day.
        public let paymentCount: Int
        /// `true` when at least one payment is due that day.
        public var hasPayments: Bool { paymentCount > 0 }
        /// `true` for the injected today.
        public let isToday: Bool
        /// `true` for ``HomeViewModel/selectedDay``.
        public let isSelected: Bool
        /// VoiceOver label: `"12 October, 2 payments, 4.900,00 Türk lirası"`,
        /// or the date only (`"13 October"`) when nothing is due; empty for a blank.
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
    /// The part of ``total`` due by the injected today: payments due today or earlier in the
    /// current month, the whole ``total`` for a past month, zero for a future month.
    ///
    /// Computed from the whole month, so ``selectedDay`` does not change it; zero after an error.
    public private(set) var dueSoFar: Money = .zero
    /// Subtotals of the cards with payments in ``month``, in the repository's card order.
    public private(set) var cardSubtotals: [CardSubtotal] = []
    /// The payments of ``month``, in schedule order; only those due on ``selectedDay`` when a day is selected.
    public private(set) var rows: [Row] = []
    /// The day of ``month`` whose payments ``rows`` shows, or `nil` for the whole month.
    /// Cleared when the month changes.
    public private(set) var selectedDay: Int?
    /// The month grid: blanks up to the 1st's weekday (the week starts on the injected
    /// calendar's `firstWeekday`), then one cell per day. Empty after a repository error.
    public private(set) var calendarDays: [CalendarDay] = []
    /// ``UpcomingMonths/defaultCount`` consecutive months with their totals.
    ///
    /// Starts at the current month while the selected month is one of them, otherwise at the
    /// selected month, so the selected month is always in the strip. Empty after a repository error.
    public private(set) var upcoming: [MonthSummary] = []
    /// `true` when the repository has at least one card; `false` before loading or after a repository error.
    public private(set) var hasCards = false

    @ObservationIgnored private let repository: any PaymentRepository
    // Kayıt/silme sonrası çağrılır (ör. hatırlatmaları yeniden planlamak için); nil ise hiçbir şey yapılmaz.
    @ObservationIgnored private let onDataChanged: (@MainActor () -> Void)?
    // Enjekte edilen bugün: ay ve gün (Card.DueDate dışarıdan kurulamaz).
    @ObservationIgnored private var todayMonth: YearMonth
    @ObservationIgnored private var todayDay: Int
    @ObservationIgnored private let calendar: Calendar
    // Haftanın ilk günü kullanıcının yerel ayarından (enjekte edilen takvim) gelir: 1 = Pazar.
    @ObservationIgnored private let firstWeekday: Int
    // Seçili gün yokken de tüm satırlar burada tutulur; `rows` bunun süzülmüş halidir.
    @ObservationIgnored private var allRows: [Row] = []

    /// Creates the view model for the month that contains `today` in `calendar`'s time zone, and loads it.
    ///
    /// `onDataChanged` runs after ``reloadAfterChange()``, i.e. after a form closes
    /// (e.g. to refresh the reminders); `nil` does nothing.
    public init(
        repository: any PaymentRepository,
        today: Date,
        calendar: Calendar,
        onDataChanged: (@MainActor () -> Void)? = nil
    ) {
        self.repository = repository
        self.onDataChanged = onDataChanged
        // YearMonth gibi: sadece saat dilimi alınır, gün Gregoryen takvimle hesaplanır.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        self.calendar = gregorian
        self.firstWeekday = calendar.firstWeekday
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

    /// Short weekday names for the grid's header, starting at the calendar's first weekday (e.g. `"Mon"`).
    public var calendarWeekdaySymbols: [String] {
        (0..<7).map { Self.weekdaySymbols[(firstWeekday - 1 + $0) % 7] }
    }

    /// The selected day as `"12 October"`, or `nil` when no day is selected.
    public var selectedDayText: String? {
        selectedDay.map { Self.dayText(day: $0, of: month) }
    }

    /// A new add-installment form on the same repository, starting at the selected ``month``.
    ///
    /// Call ``reload()`` after it saves, so the new payment shows.
    public func makeAddInstallmentModel(locale: Locale = .current) -> AddInstallmentViewModel {
        AddInstallmentViewModel(repository: repository, initialMonth: month, locale: locale)
    }

    /// A new add-subscription form on the same repository, starting at the selected ``month``.
    ///
    /// Call ``reload()`` after it saves, so the new payment shows.
    public func makeAddSubscriptionModel(locale: Locale = .current) -> AddSubscriptionViewModel {
        AddSubscriptionViewModel(repository: repository, initialMonth: month, locale: locale)
    }

    /// A new add-card form on the same repository.
    ///
    /// Call ``reload()`` after it saves, so ``hasCards`` and the card names update.
    public func makeAddCardModel() -> AddCardViewModel {
        AddCardViewModel(repository: repository)
    }

    /// An edit form for the installment with `id`, or `nil` when it is not saved or cannot be loaded.
    ///
    /// Call ``reload()`` after it saves or deletes.
    public func makeEditInstallmentModel(id: InstallmentItem.ID, locale: Locale = .current) -> AddInstallmentViewModel? {
        guard let item = (try? repository.installments())?.first(where: { $0.id == id }) else { return nil }
        return AddInstallmentViewModel(repository: repository, editing: item, locale: locale)
    }

    /// An edit form for the subscription with `id`, or `nil` when it is not saved or cannot be loaded.
    ///
    /// Call ``reload()`` after it saves or deletes.
    public func makeEditSubscriptionModel(id: SubscriptionItem.ID, locale: Locale = .current) -> AddSubscriptionViewModel? {
        guard let item = (try? repository.subscriptions())?.first(where: { $0.id == id }) else { return nil }
        return AddSubscriptionViewModel(repository: repository, editing: item, locale: locale)
    }

    /// An edit form for the card with `id`, or `nil` when it is not saved or cannot be loaded.
    ///
    /// Call ``reload()`` after it saves or deletes.
    public func makeEditCardModel(id: Card.ID) -> AddCardViewModel? {
        guard let card = (try? repository.cards())?.first(where: { $0.id == id }) else { return nil }
        return AddCardViewModel(repository: repository, editing: card)
    }

    /// Selects `month` (e.g. a tapped chip of ``upcoming``) and reloads; clears ``selectedDay``.
    public func select(month: YearMonth) {
        change(to: month)
    }

    /// Selects the previous month and reloads; clears ``selectedDay``.
    public func showPreviousMonth() {
        change(to: month.adding(months: -1))
    }

    /// Selects the next month and reloads; clears ``selectedDay``.
    public func showNextMonth() {
        change(to: month.adding(months: 1))
    }

    /// Shows only the payments due on `day` of ``month``; selecting the selected day again clears it.
    ///
    /// Days without payments can be selected too (``rows`` is then empty). Days outside the month are ignored.
    public func select(day: Int) {
        guard (1...month.numberOfDays).contains(day) else { return }
        selectedDay = selectedDay == day ? nil : day
        applySelection()
    }

    /// Clears ``selectedDay``, so ``rows`` shows the whole month again.
    public func clearSelectedDay() {
        guard selectedDay != nil else { return }
        selectedDay = nil
        applySelection()
    }

    // Ay değişince gün seçimi temizlenir (başka ayın günü anlamsız).
    private func change(to newMonth: YearMonth) {
        if newMonth != month { selectedDay = nil }
        month = newMonth
        reload()
    }

    /// Moves "today" to `date` (e.g. when the app becomes active after midnight) and reloads.
    ///
    /// If the selected month was the old current month, the new current month is selected;
    /// a month the user navigated to is kept.
    public func updateToday(_ date: Date) {
        let newMonth = YearMonth(date: date, calendar: calendar)
        // Kullanıcı başka aya geçmediyse seçim yeni "bu ay"ı izler.
        if month == todayMonth, newMonth != month {
            month = newMonth
            selectedDay = nil
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
            hasCards = !cards.isEmpty
        } catch {
            // Hata sessizce boş liste olmaz; ekranda hata durumu gösterilir.
            schedule = nil
            total = .zero
            dueSoFar = .zero
            cardSubtotals = []
            allRows = []
            rows = []
            calendarDays = []
            upcoming = []
            hasCards = false
            state = .error(message: Self.loadErrorMessage)
        }
    }

    /// Reloads after a form closed (the repository may have changed), then runs `onDataChanged`.
    public func reloadAfterChange() {
        reload()
        onDataChanged?()
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
        allRows = schedule.entries.enumerated().map { index, entry in
            makeRow(entry, index: index, cardName: entry.cardID.flatMap { namesByID[$0] })
        }
        self.schedule = schedule
        total = schedule.total
        dueSoFar = Self.dueSoFar(
            of: schedule.entries, month: schedule.month, todayMonth: todayMonth, todayDay: todayDay
        )
        // Durum ayın tamamına göre: seçili günün boş olması ayı "boş" yapmaz.
        state = schedule.entries.isEmpty ? .empty : .loaded
        applySelection()
    }

    // Satırları seçili güne süzer ve takvimi (seçim vurgusu dahil) yeniden kurar.
    private func applySelection() {
        if let selectedDay {
            rows = allRows.filter { $0.entry.dueDate.day == selectedDay }
        } else {
            rows = allRows
        }
        calendarDays = schedule.map(makeCalendarDays) ?? []
    }

    /// The sum of `entries` (all due in `month`) due on or before `todayDay` of `todayMonth`.
    ///
    /// Pure: a month before `todayMonth` gives the whole sum, a later month gives zero.
    nonisolated static func dueSoFar(
        of entries: [MonthlySchedule.Entry], month: YearMonth, todayMonth: YearMonth, todayDay: Int
    ) -> Money {
        // Geçmiş ayın tamamı vadesi gelmiş, gelecek ayın hiçbiri gelmemiştir.
        let due: [MonthlySchedule.Entry]
        if month < todayMonth {
            due = entries
        } else if month > todayMonth {
            due = []
        } else {
            due = entries.filter { $0.dueDate.day <= todayDay }
        }
        return due.reduce(Money.zero) { $0 + $1.amount }
    }

    private func makeCalendarDays(_ schedule: MonthlySchedule) -> [CalendarDay] {
        let daysByNumber = Dictionary(schedule.days.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        // 1'inin haftanın ilk gününden kaç gün sonra geldiği = baştaki boş hücre sayısı.
        let blanks = (schedule.month.weekdayOfFirstDay - firstWeekday + 7) % 7
        var cells = (0..<blanks).map { index in
            CalendarDay(
                id: index, day: nil, total: .zero, paymentCount: 0,
                isToday: false, isSelected: false, accessibilityLabel: ""
            )
        }
        for day in 1...schedule.month.numberOfDays {
            let group = daysByNumber[day]
            let count = group?.entries.count ?? 0
            let total = group?.total ?? .zero
            let date = Self.dayText(day: day, of: schedule.month)
            // Ödemesiz gün sadece tarihi okur.
            let label = count == 0
                ? date
                : "\(date), \(count) \(count == 1 ? "payment" : "payments"), \(AmountText.spokenLabel(total))"
            cells.append(CalendarDay(
                id: blanks + day - 1, day: day, total: total, paymentCount: count,
                isToday: schedule.month == todayMonth && day == todayDay,
                isSelected: day == selectedDay,
                accessibilityLabel: label
            ))
        }
        return cells
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
        let dueText = Self.dayText(day: entry.dueDate.day, of: entry.dueDate.month)
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

    // "12 October" biçimi; satırlar, takvim ve seçili gün aynı metni kullanır.
    private nonisolated static func dayText(day: Int, of month: YearMonth) -> String {
        "\(day) \(monthNames[month.month - 1])"
    }

    // Ekleme formu da aynı ay başlığını kullanır.
    nonisolated static func title(of month: YearMonth) -> String {
        "\(monthNames[month.month - 1]) \(month.year)"
    }

    // Ay adları sabit (İngilizce); cihaz diline bağlı değil, ekran metinleriyle uyumlu.
    private nonisolated static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    // Calendar.weekday sırası: indeks 0 = Pazar (weekday 1).
    private nonisolated static let weekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
}
