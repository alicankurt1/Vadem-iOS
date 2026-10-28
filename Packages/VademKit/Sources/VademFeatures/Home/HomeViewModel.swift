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
    public nonisolated static var noCardText: String { String(localized: "No card", bundle: .module) }
    /// The message of the ``State/error(message:)`` state.
    public nonisolated static var loadErrorMessage: String {
        String(localized: "Your payments could not be loaded.", bundle: .module)
    }
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
    // Ayarlar sayfasının bağımlılıkları; verilmezse bellek içi depo (zamanlayıcı yok), açılışlar arasında korunur.
    @ObservationIgnored private let settings: SettingsDependencies
    // Asistan motoru; nil ise işletim sisteminin sunduğu motor bu deponun verisiyle kurulur.
    @ObservationIgnored private let assistantEngineOverride: (any AssistantEngine)?
    // İlk kullanımda kurulan sistem motoru; her gövde değerlendirmesinde yeniden kurulmaz.
    @ObservationIgnored private var systemAssistantEngine: (any AssistantEngine)?
    // Enjekte edilen bugün: ay ve gün (Card.DueDate dışarıdan kurulamaz).
    @ObservationIgnored private var todayMonth: YearMonth
    @ObservationIgnored private var todayDay: Int
    @ObservationIgnored private let calendar: Calendar
    // Haftanın ilk günü kullanıcının yerel ayarından (enjekte edilen takvim) gelir: 1 = Pazar.
    @ObservationIgnored private let firstWeekday: Int
    // Seçili gün yokken de tüm satırlar burada tutulur; `rows` bunun süzülmüş halidir.
    @ObservationIgnored private var allRows: [Row] = []

    /// The card chosen in the last saved add flow (`nil` = "No card" or none yet); the next flow
    /// preselects it. Kept in memory for the session only.
    @ObservationIgnored public internal(set) var lastUsedCardID: Card.ID?

    /// Creates the view model for the month that contains `today` in `calendar`'s time zone, and loads it.
    ///
    /// `onDataChanged` runs after ``reloadAfterChange()``, i.e. after a form closes
    /// (e.g. to refresh the reminders); `nil` does nothing. `settings` backs the settings sheet
    /// (``makeSettingsModel()``); `nil` uses an in-memory store without a scheduler.
    /// `assistant` answers in the assistant chat (``makeAssistantModel()``); `nil` uses the engine
    /// the OS offers (``AssistantEngineFactory/makeSystemEngine(snapshot:)``) on this repository.
    public init(
        repository: any PaymentRepository,
        today: Date,
        calendar: Calendar,
        onDataChanged: (@MainActor () -> Void)? = nil,
        settings: SettingsDependencies? = nil,
        assistant: (any AssistantEngine)? = nil
    ) {
        self.repository = repository
        self.onDataChanged = onDataChanged
        self.settings = settings ?? .inMemory()
        self.assistantEngineOverride = assistant
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
        let symbols = VademLocalization.shortWeekdaySymbols()
        return (0..<7).map { symbols[(firstWeekday - 1 + $0) % 7] }
    }

    /// The selected day as `"12 October"`, or `nil` when no day is selected.
    public var selectedDayText: String? {
        selectedDay.map { Self.dayText(day: $0, of: month) }
    }

    /// A new settings sheet model on the injected ``SettingsDependencies``, with the Cards screen
    /// on the same repository. Call ``reloadAfterChange()`` after the sheet closes.
    public func makeSettingsModel() -> SettingsViewModel {
        SettingsViewModel(dependencies: settings, repository: repository)
    }

    /// A new Analytics screen model on the same repository, starting at the current month.
    ///
    /// It loads when its screen appears; call ``AnalyticsViewModel/reload()`` after a form closes.
    public func makeAnalyticsModel() -> AnalyticsViewModel {
        AnalyticsViewModel(repository: repository, currentMonth: todayMonth)
    }

    /// `true` when Home offers the assistant: the engine's availability is not
    /// ``AssistantAvailability/unsupportedOS`` (an unavailable model still opens its explanation).
    public var showsAssistant: Bool {
        assistantEngine.availability != .unsupportedOS
    }

    /// A new assistant chat model with an empty conversation; every question reads the repository afresh.
    public func makeAssistantModel() -> AssistantViewModel {
        AssistantViewModel(engine: assistantEngine)
    }

    // Verilen motor, yoksa işletim sisteminin motoru (bir kez kurulur, sonra yeniden kullanılır);
    // her soruda depodan taze anlık görüntü alınır.
    private var assistantEngine: any AssistantEngine {
        if let assistantEngineOverride { return assistantEngineOverride }
        if let systemAssistantEngine { return systemAssistantEngine }
        let engine = AssistantEngineFactory.makeSystemEngine { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            return try self.assistantQueries()
        }
        systemAssistantEngine = engine
        return engine
    }

    private func assistantQueries() throws -> AssistantQueries {
        AssistantQueries(
            cards: try repository.cards(),
            installments: try repository.installments(),
            subscriptions: try repository.subscriptions()
        )
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

    /// A new subscription add flow on the same repository: first month is the selected ``month``,
    /// renewal day is today, ``lastUsedCardID`` is preselected; a save updates ``lastUsedCardID``.
    ///
    /// `start` and `amount` open the flow at a later step with an amount (UI check).
    /// Call ``reload()`` after it saves, so the new payment shows.
    public func makeSubscriptionFlowModel(
        start: SubscriptionFlowStep = .amount, amount: Decimal? = nil, locale: Locale = .current
    ) -> SubscriptionFlowViewModel {
        let form = AddSubscriptionViewModel(
            repository: repository, initialMonth: month, initialRenewalDay: todayDay, locale: locale
        )
        return SubscriptionFlowViewModel(
            form: form, start: start, lastUsedCardID: lastUsedCardID, amount: amount, locale: locale
        ) { [weak self] cardID in
            self?.lastUsedCardID = cardID
        }
    }

    /// A new add-card form on the same repository.
    ///
    /// Call ``reload()`` after it saves, so ``hasCards`` and the card names update.
    public func makeAddCardModel() -> AddCardViewModel {
        AddCardViewModel(repository: repository)
    }

    /// The saved cards in the repository's order, for the add flow's card picker; empty when they cannot be loaded.
    func pickerCards() -> [Card] {
        (try? repository.cards()) ?? []
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
                : Self.listText([date, Self.paymentCountText(count), AmountText.spokenLabel(total)])
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
            accessibilityLabel: Self.listText([title, AmountText.spokenLabel(schedule.total)])
        )
    }

    private func makeRow(_ entry: MonthlySchedule.Entry, index: Int, cardName: String?) -> Row {
        let cardText = cardName ?? Self.noCardText
        let installmentText: String?
        let spokenInstallment: String?
        switch entry.kind {
        case .installment(let number, let count):
            installmentText = "\(number)/\(count)"
            spokenInstallment = String(
                localized: "installment \(number) of \(count)", bundle: .module,
                comment: "Spoken installment number in a payment row, e.g. installment 3 of 12"
            )
        case .subscription:
            installmentText = nil
            spokenInstallment = nil
        }
        let kind = chipKind(for: entry.dueDate)
        let chipText = chipText(for: kind, dueDate: entry.dueDate)
        let dueText = Self.dayText(day: entry.dueDate.day, of: entry.dueDate.month)
        // VoiceOver satırı tek öğe olarak okur; "₺" yerine okunabilir tutar kullanılır.
        let parts = [entry.title, spokenInstallment, AmountText.spokenLabel(entry.amount),
                     String(localized: "due \(dueText)", bundle: .module, comment: "Spoken due date, e.g. due 15 October"),
                     cardText, chipText].compactMap { $0 }
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
            accessibilityLabel: Self.listText(parts)
        )
    }

    private func chipText(for kind: DueChip.Kind, dueDate: Card.DueDate) -> String {
        switch kind {
        case .overdue: return String(localized: "Overdue", bundle: .module, comment: "Due chip")
        case .today: return String(localized: "Today", bundle: .module, comment: "Due chip")
        case .soon:
            let days = daysFromToday(to: dueDate)
            return days == 1
                ? String(localized: "Tomorrow", bundle: .module, comment: "Due chip")
                : String(localized: "In \(days) days", bundle: .module, comment: "Due chip, 2 or more days ahead")
        case .later: return String(localized: "Later", bundle: .module, comment: "Due chip")
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
    // Ay adları ekran metinlerinin dilinden gelir (VademLocalization.locale).
    private nonisolated static func dayText(day: Int, of month: YearMonth) -> String {
        VademLocalization.dayTitle(day: day, of: month)
    }

    // Ekleme formu da aynı ay başlığını kullanır.
    nonisolated static func title(of month: YearMonth) -> String {
        VademLocalization.monthTitle(month)
    }

    // "1 payment" / "4 payments": katalogdaki çoğul varyasyonlarından. Derlenmiş katalog yokken
    // (`swift test`) Foundation'ın otomatik dil bilgisi uyumu ("inflect") İngilizce çoğulu kurar.
    nonisolated static func paymentCountText(_ count: Int) -> String {
        String(AttributedString(
            localized: "^[\(count) payment](inflect: true)", bundle: .module,
            comment: "Number of payments on a calendar day; plural variations in the catalog"
        ).characters)
    }

    // VoiceOver etiketinin parçaları virgülle birleşir.
    nonisolated static func listText(_ parts: [String]) -> String {
        parts.joined(separator: ", ")
    }
}
