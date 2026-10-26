import Foundation
import Testing
import VademCore
import VademFeatures

/// #137: grafiğin VoiceOver özeti ve ay seçimi (ayarlanabilir eylem).
@MainActor
@Suite("Analytics accessibility")
struct AnalyticsAccessibilityTests {
    private static func ym(_ year: Int, _ month: Int) -> YearMonth { YearMonth(year: year, month: month)! }

    private static func total(_ month: YearMonth, _ installments: Decimal, _ subscriptions: Decimal = 0)
        -> SpendingAnalytics.MonthTotal
    {
        .init(month: month, installments: Money(installments), subscriptions: Money(subscriptions))
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func loadedModel() -> AnalyticsViewModel {
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
        let model = AnalyticsViewModel(repository: InMemoryPaymentRepository(), today: today, calendar: calendar)
        model.reload()
        return model
    }

    // MARK: chartSummary

    @Test("Summary without months is only the base sentence")
    func summaryEmpty() {
        let base = AnalyticsViewModel.chartSummary(for: [])
        #expect(!base.isEmpty)
        #expect(!base.contains("Highest"))
        #expect(!base.contains("Total"))
    }

    @Test("Summary with all-zero months is the base sentence")
    func summaryAllZero() {
        let months = (0..<12).map { Self.total(Self.ym(2026, 10).adding(months: $0), 0) }
        #expect(AnalyticsViewModel.chartSummary(for: months) == AnalyticsViewModel.chartSummary(for: []))
    }

    @Test("Summary names the 12-month total and the highest month")
    func summaryTotalAndHighest() {
        let months = [
            Self.total(Self.ym(2026, 10), 1000, 500),
            Self.total(Self.ym(2026, 11), 4000, 250),  // en yüksek: 4.250
            Self.total(Self.ym(2026, 12), 0, 20_000.50),
        ]
        let summary = AnalyticsViewModel.chartSummary(for: months)
        // Toplam 1.500 + 4.250 + 20.000,50 = 25.750,50
        #expect(summary.contains("25.750,50"))
        // En yüksek ay 20.000,50 olan Aralık.
        #expect(summary.contains("20.000,50"))
        #expect(summary.contains(AnalyticsViewModel.title(of: Self.ym(2026, 12))))
        // Temel cümleden uzun olmalı (toplam ve en yüksek ay eklenir).
        #expect(summary.count > AnalyticsViewModel.chartSummary(for: []).count)
    }

    @Test("Ties for the highest month go to the earlier month")
    func summaryTie() {
        let months = [
            Self.total(Self.ym(2026, 3), 100),
            Self.total(Self.ym(2026, 4), 700),
            Self.total(Self.ym(2026, 5), 700),
        ]
        let summary = AnalyticsViewModel.chartSummary(for: months)
        #expect(summary.contains(AnalyticsViewModel.title(of: Self.ym(2026, 4))))
        #expect(!summary.contains(AnalyticsViewModel.title(of: Self.ym(2026, 5))))
    }

    @Test("Single month: its total is both total and highest")
    func summarySingle() {
        let summary = AnalyticsViewModel.chartSummary(for: [Self.total(Self.ym(2027, 1), 12.34)])
        #expect(summary.contains("12,34"))
        #expect(summary.contains(AnalyticsViewModel.title(of: Self.ym(2027, 1))))
    }

    // MARK: selectMonth(offsetBy:)

    @Test("Offset moves the selection along the months", arguments: [1, 2, -1, -3])
    func offsetMoves(offset: Int) {
        let model = Self.loadedModel()  // seçili: Ekim 2026 (ilk ay)
        model.selectMonth(offsetBy: 3)  // Ocak 2027
        #expect(model.selectedMonth == Self.ym(2027, 1))
        model.selectMonth(offsetBy: offset)
        #expect(model.selectedMonth == Self.ym(2027, 1).adding(months: offset))
    }

    @Test("Selection stops at the first month")
    func clampsAtStart() {
        let model = Self.loadedModel()
        model.selectMonth(offsetBy: -1)
        model.selectMonth(offsetBy: -100)
        #expect(model.selectedMonth == Self.ym(2026, 10))
    }

    @Test("Selection stops at the last month")
    func clampsAtEnd() {
        let model = Self.loadedModel()
        model.selectMonth(offsetBy: 100)
        #expect(model.selectedMonth == Self.ym(2027, 9))
        model.selectMonth(offsetBy: 1)
        #expect(model.selectedMonth == Self.ym(2027, 9))
    }

    @Test("Zero offset keeps the selection")
    func zeroOffset() {
        let model = Self.loadedModel()
        model.selectMonth(offsetBy: 0)
        #expect(model.selectedMonth == Self.ym(2026, 10))
    }

    @Test("Offset before loading does nothing")
    func offsetBeforeLoad() {
        let today = Self.calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
        let model = AnalyticsViewModel(repository: InMemoryPaymentRepository(), today: today, calendar: Self.calendar)
        model.selectMonth(offsetBy: 1)
        #expect(model.selectedMonth == Self.ym(2026, 10))
    }
}
