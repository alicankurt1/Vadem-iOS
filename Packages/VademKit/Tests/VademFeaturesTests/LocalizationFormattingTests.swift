import Foundation
import Testing
import VademCore
@testable import VademFeatures

/// Yerel ayara bağlı tarih metinleri ve çoğul metinleri (İngilizce çıktı değişmemeli).
@Suite("Localized formatting")
struct LocalizationFormattingTests {
    private static let en = Locale(identifier: "en_US")
    private static let tr = Locale(identifier: "tr_TR")

    private static func month(_ year: Int, _ month: Int) -> YearMonth { YearMonth(year: year, month: month)! }

    @Test("Month title reads month name and year in the locale", arguments: [
        (2026, 10, "en_US", "October 2026"),
        (2026, 1, "en_US", "January 2026"),
        (2026, 12, "en_US", "December 2026"),
        (2024, 2, "en_US", "February 2024"),
        (2026, 10, "tr_TR", "Ekim 2026"),
        (2026, 1, "tr_TR", "Ocak 2026"),
    ])
    func monthTitle(year: Int, month: Int, locale: String, expected: String) {
        #expect(VademLocalization.monthTitle(Self.month(year, month), locale: Locale(identifier: locale)) == expected)
    }

    @Test("Short month title", arguments: [
        (10, "en_US", "Oct"), (1, "en_US", "Jan"), (12, "en_US", "Dec"), (10, "tr_TR", "Eki"),
    ])
    func shortMonthTitle(month: Int, locale: String, expected: String) {
        #expect(VademLocalization.shortMonthTitle(Self.month(2026, month), locale: Locale(identifier: locale)) == expected)
    }

    @Test("Day title puts the day before the month name, including month ends and leap day", arguments: [
        (12, 2026, 10, "en_US", "12 October"),
        (1, 2026, 1, "en_US", "1 January"),
        (31, 2026, 12, "en_US", "31 December"),
        (29, 2024, 2, "en_US", "29 February"),
        (28, 2026, 2, "en_US", "28 February"),
        (12, 2026, 10, "tr_TR", "12 Ekim"),
    ])
    func dayTitle(day: Int, year: Int, month: Int, locale: String, expected: String) {
        #expect(VademLocalization.dayTitle(day: day, of: Self.month(year, month), locale: Locale(identifier: locale)) == expected)
    }

    @Test("Weekday symbols run Sunday to Saturday in English")
    func weekdaySymbols() {
        #expect(VademLocalization.shortWeekdaySymbols(locale: Self.en) == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        #expect(VademLocalization.shortWeekdaySymbols(locale: Self.tr).count == 7)
        #expect(VademLocalization.shortWeekdaySymbols(locale: Self.tr) != VademLocalization.shortWeekdaySymbols(locale: Self.en))
    }

    @Test("Catalog bundle resolves to English for tests")
    func englishDefault() {
        #expect(VademLocalization.locale.identifier.hasPrefix("en"))
    }

    @Test("Payment count text pluralizes", arguments: [
        (0, "0 payments"), (1, "1 payment"), (2, "2 payments"), (4, "4 payments"), (21, "21 payments"),
    ])
    func paymentCount(count: Int, expected: String) {
        #expect(HomeViewModel.paymentCountText(count) == expected)
    }

    // MARK: Bildirim metni

    private static func reminders(subscriptions count: Int, kind: PlannedReminder.Kind) -> [PlannedReminder] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let october = YearMonth(year: 2026, month: 10)!
        let items = (0..<count).map { index in
            let value = Subscription(amount: Money(Decimal(100)), period: .monthly, renewalDay: 5, firstMonth: october)!
            return SubscriptionItem(id: UUID(), title: index == 0 ? "Rent" : "S\(index)", cardID: nil, subscription: value)!
        }
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 8))!
        return NotificationPlanner.plan(
            now: now, calendar: calendar, cards: [], installments: [], subscriptions: items,
            lookaheadMonths: 1, kinds: [kind], formatAmount: { "<\($0.amount)>" }
        )
    }

    @Test("Reminder titles")
    func reminderTitles() throws {
        let today = try #require(Self.reminders(subscriptions: 1, kind: .dueDay).first)
        let tomorrow = try #require(Self.reminders(subscriptions: 1, kind: .dayBefore).first)
        #expect(ReminderText.title(for: today) == "Payment due today")
        #expect(ReminderText.title(for: tomorrow) == "Payment due tomorrow")
    }

    @Test("A single payment reminder names the payment and the amount")
    func reminderSingle() throws {
        let today = try #require(Self.reminders(subscriptions: 1, kind: .dueDay).first)
        let tomorrow = try #require(Self.reminders(subscriptions: 1, kind: .dayBefore).first)
        #expect(ReminderText.body(for: today, formatAmount: { "<\($0.amount)>" }) == "Rent due today, <100>")
        #expect(ReminderText.body(for: tomorrow, formatAmount: { "<\($0.amount)>" }) == "Rent due tomorrow, <100>")
    }

    @Test("Several payments are counted in plural with the total", arguments: [2, 3, 11])
    func reminderPlural(count: Int) throws {
        let today = try #require(Self.reminders(subscriptions: count, kind: .dueDay).first)
        let tomorrow = try #require(Self.reminders(subscriptions: count, kind: .dayBefore).first)
        let total = "<\(count * 100)>"
        #expect(ReminderText.body(for: today, formatAmount: { "<\($0.amount)>" }) == "\(count) payments due today, \(total) total")
        #expect(ReminderText.body(for: tomorrow, formatAmount: { "<\($0.amount)>" }) == "\(count) payments due tomorrow, \(total) total")
    }

    @Test("Planner text and localized text agree in English")
    func plannerAgreement() throws {
        for count in [1, 3] {
            for kind in PlannedReminder.Kind.allCases {
                let reminder = try #require(Self.reminders(subscriptions: count, kind: kind).first)
                #expect(ReminderText.title(for: reminder) == reminder.title)
                #expect(ReminderText.body(for: reminder, formatAmount: { "<\($0.amount)>" }) == reminder.body)
            }
        }
    }
}
