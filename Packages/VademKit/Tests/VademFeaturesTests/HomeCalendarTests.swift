import Foundation
import Testing
import VademCore
import VademFeatures

@MainActor
@Suite("HomeViewModel calendar")
struct HomeCalendarTests {
    // MARK: Yardımcılar

    private static func calendar(firstWeekday: Int = 1) -> Calendar {
        var calendar = HomeSampleData.calendar
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        HomeSampleData.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    // Örnek veri (12 Ekim 2026, Pazar ilk gün): ödemeler 8 (4000), 12 (900), 15 (249,99), 25 (25000).
    private static func sampleModel(firstWeekday: Int = 1) -> HomeViewModel {
        HomeViewModel(repository: HomeSampleData.makeRepository(), today: HomeSampleData.today, calendar: calendar(firstWeekday: firstWeekday))
    }

    private static func emptyModel(_ year: Int, _ month: Int, firstWeekday: Int = 1) -> HomeViewModel {
        HomeViewModel(repository: InMemoryPaymentRepository(), today: date(year, month, 10), calendar: calendar(firstWeekday: firstWeekday))
    }

    private static func twoPaymentsModel() -> HomeViewModel {
        let repository = InMemoryPaymentRepository()
        let october = YearMonth(year: 2026, month: 10)!
        for (index, amount) in [Decimal(100), Decimal(5050) / 100].enumerated() {
            let value = Subscription(amount: Money(amount), period: .monthly, renewalDay: 5, firstMonth: october)!
            try! repository.save(SubscriptionItem(id: UUID(), title: "S\(index)", cardID: nil, subscription: value)!)
        }
        return HomeViewModel(repository: repository, today: HomeSampleData.today, calendar: calendar())
    }

    private static func cell(_ model: HomeViewModel, day: Int) -> HomeViewModel.CalendarDay? {
        model.calendarDays.first { $0.day == day }
    }

    // MARK: Izgara geometrisi

    @Test("Grid has the right blanks and month length", arguments: [
        // yıl, ay, ilk gün, beklenen boşluk, gün sayısı
        (2026, 10, 1, 4, 31),  // 1 Ekim Perşembe, Pazar başlangıçlı
        (2026, 10, 2, 3, 31),  // Pazartesi başlangıçlı
        (2026, 10, 7, 5, 31),  // Cumartesi başlangıçlı
        (2024, 2, 1, 4, 29),   // artık yıl Şubat
        (2023, 2, 1, 3, 28),   // artık olmayan Şubat
        (2026, 2, 2, 6, 28),   // 1 Şubat 2026 Pazar; Pazartesi başlangıçlı -> 6 boşluk
        (2026, 11, 1, 0, 30),  // 1 Kasım 2026 Pazar; boşluk yok
    ])
    func gridShape(year: Int, month: Int, firstWeekday: Int, blanks: Int, days: Int) {
        let model = Self.emptyModel(year, month, firstWeekday: firstWeekday)
        let cells = model.calendarDays
        #expect(cells.count == blanks + days)
        #expect(cells.prefix(blanks).allSatisfy { $0.day == nil })
        #expect(cells.dropFirst(blanks).map(\.day) == (1...days).map { Optional($0) })
        #expect(Set(cells.map(\.id)).count == cells.count)
    }

    @Test("Weekday symbols start at the calendar's first weekday", arguments: [
        (1, ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]),
        (2, ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]),
        (7, ["Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri"]),
    ])
    func weekdaySymbols(firstWeekday: Int, expected: [String]) {
        #expect(Self.sampleModel(firstWeekday: firstWeekday).calendarWeekdaySymbols == expected)
    }

    // MARK: Işaretler ve toplamlar

    @Test("Days with payments are marked with the exact total; other days are not")
    func marksAndTotals() {
        let model = Self.sampleModel()
        let expected: [Int: Money] = [8: Money(4000), 12: Money(900), 15: Money(Decimal(24_999) / 100), 25: Money(25_000)]
        for day in 1...31 {
            let cell = Self.cell(model, day: day)
            #expect(cell?.hasPayments == (expected[day] != nil), "day \(day)")
            #expect(cell?.total == expected[day] ?? .zero, "day \(day)")
        }
    }

    @Test("A day's count and total add up several entries")
    func multiplePayments() {
        let cell = Self.cell(Self.twoPaymentsModel(), day: 5)
        #expect(cell?.paymentCount == 2)
        #expect(cell?.total == Money(Decimal(15050) / 100))
        #expect(cell?.hasPayments == true)
    }

    @Test("Only the injected today is flagged, and only in its month")
    func todayFlag() {
        let model = Self.sampleModel()
        #expect(model.calendarDays.filter(\.isToday).compactMap(\.day) == [12])
        model.showNextMonth()
        #expect(model.calendarDays.contains { $0.isToday } == false)
        model.showPreviousMonth()
        #expect(model.calendarDays.filter(\.isToday).compactMap(\.day) == [12])
    }

    // MARK: VoiceOver

    @Test("Accessibility labels: plural, singular, date only, blank")
    func labels() {
        let two = Self.twoPaymentsModel()
        #expect(Self.cell(two, day: 5)?.accessibilityLabel == "5 October, 2 payments, 150,50 Türk lirası")
        #expect(Self.cell(two, day: 6)?.accessibilityLabel == "6 October")
        let sample = Self.sampleModel()
        #expect(Self.cell(sample, day: 12)?.accessibilityLabel == "12 October, 1 payment, 900,00 Türk lirası")
        #expect(Self.cell(sample, day: 13)?.accessibilityLabel == "13 October")
        #expect(sample.calendarDays.first?.day == nil)
        #expect(sample.calendarDays.first?.accessibilityLabel == "")
    }

    // MARK: Seçim

    @Test("Selecting a day filters rows to that day and highlights it")
    func selectFilters() {
        let model = Self.sampleModel()
        model.select(day: 12)
        #expect(model.selectedDay == 12)
        #expect(model.selectedDayText == "12 October")
        #expect(model.rows.map(\.entry.title) == ["Gym"])
        #expect(model.calendarDays.filter(\.isSelected).compactMap(\.day) == [12])
    }

    @Test("Selecting the same day again clears the filter")
    func toggle() {
        let model = Self.sampleModel()
        let all = model.rows
        model.select(day: 15)
        model.select(day: 15)
        #expect(model.selectedDay == nil)
        #expect(model.selectedDayText == nil)
        #expect(model.rows == all)
        #expect(model.calendarDays.contains { $0.isSelected } == false)
    }

    @Test("Selecting another day switches the filter")
    func switchDay() {
        let model = Self.sampleModel()
        model.select(day: 12)
        model.select(day: 25)
        #expect(model.selectedDay == 25)
        #expect(model.rows.map(\.entry.title) == ["Rent"])
    }

    @Test("A day without payments is selectable, gives no rows and keeps the month loaded")
    func emptyDay() {
        let model = Self.sampleModel()
        model.select(day: 13)
        #expect(model.selectedDay == 13)
        #expect(model.rows.isEmpty)
        #expect(model.state == .loaded)
        #expect(Self.cell(model, day: 13)?.isSelected == true)
    }

    @Test("Totals and subtotals ignore the day filter")
    func totalsUnfiltered() {
        let model = Self.sampleModel()
        let total = model.total
        let subtotals = model.cardSubtotals
        model.select(day: 12)
        #expect(model.total == total)
        #expect(model.cardSubtotals == subtotals)
    }

    @Test("clearSelectedDay restores all rows and is harmless without a selection")
    func clear() {
        let model = Self.sampleModel()
        let all = model.rows
        model.clearSelectedDay()
        #expect(model.rows == all)
        model.select(day: 8)
        model.clearSelectedDay()
        #expect(model.selectedDay == nil)
        #expect(model.rows == all)
    }

    @Test("Days outside the month are ignored", arguments: [0, -1, 32, 100])
    func outOfRange(day: Int) {
        let model = Self.sampleModel()
        model.select(day: day)
        #expect(model.selectedDay == nil)
        #expect(model.rows.count == 4)
    }

    @Test("Day 31 is not selectable in a 30-day month")
    func monthLengthBound() {
        let model = Self.emptyModel(2026, 11)
        model.select(day: 31)
        #expect(model.selectedDay == nil)
        model.select(day: 30)
        #expect(model.selectedDay == 30)
    }

    // MARK: Ay değişimi

    @Test("Changing the month clears the selection", arguments: ["next", "previous", "chip"])
    func monthChangeClears(how: String) {
        let model = Self.sampleModel()
        model.select(day: 12)
        switch how {
        case "next": model.showNextMonth()
        case "previous": model.showPreviousMonth()
        default: model.select(month: YearMonth(year: 2026, month: 12)!)
        }
        #expect(model.selectedDay == nil)
        #expect(model.calendarDays.contains { $0.isSelected } == false)
        // Seçimsiz gezen bir modelle aynı satırlar: filtre sızmaz.
        let reference = Self.sampleModel()
        switch how {
        case "next": reference.showNextMonth()
        case "previous": reference.showPreviousMonth()
        default: reference.select(month: YearMonth(year: 2026, month: 12)!)
        }
        #expect(model.rows == reference.rows)
    }

    @Test("Going back to a month does not restore an old selection")
    func noRestore() {
        let model = Self.sampleModel()
        model.select(day: 12)
        model.showNextMonth()
        model.showPreviousMonth()
        #expect(model.selectedDay == nil)
        #expect(model.rows.count == 4)
    }

    @Test("Grid follows the selected month")
    func gridFollowsMonth() {
        let model = Self.sampleModel()
        model.select(month: YearMonth(year: 2026, month: 11)!)
        #expect(model.calendarDays.compactMap(\.day).count == 30)
        #expect(model.calendarDays.prefix { $0.day == nil }.count == 0)
    }
}
