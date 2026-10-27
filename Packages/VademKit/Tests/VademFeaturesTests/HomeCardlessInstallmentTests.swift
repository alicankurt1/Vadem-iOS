import Foundation
import Testing
import VademCore
import VademFeatures

// Kartsız taksit Home'da (#155): kart adı yerine "No card", doğru vade günü.
@MainActor
@Suite("Home with a card-less installment")
struct HomeCardlessInstallmentTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func today(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func model(day: Int, count: Int = 3, total: Decimal = 300) throws -> HomeViewModel {
        let repository = InMemoryPaymentRepository()
        let plan = try #require(InstallmentPlan(total: Money(total), count: count, firstMonth: YearMonth(year: 2026, month: 10)!))
        let item = try #require(InstallmentItem(title: "Okul", cardID: nil, paymentDay: day, plan: plan))
        try repository.save(item)
        return HomeViewModel(repository: repository, today: Self.today(2026, 10, 12), calendar: Self.calendar)
    }

    @Test("A card-less installment shows as a row with No card, its number and its due day")
    func row() throws {
        let home = try model(day: 20)
        let row = try #require(home.rows.first)
        #expect(home.rows.count == 1)
        #expect(row.title == "Okul")
        #expect(row.cardText == HomeViewModel.noCardText)
        #expect(row.installmentText == "1/3")
        #expect(row.amount == Money(100))
        #expect(row.entry.dueDate.day == 20)
        #expect(row.dueText == "20 October")
        #expect(row.accessibilityLabel.contains("20 October"))
    }

    @Test("Payment day 31 lands on the last day of a shorter month")
    func clampedDay() throws {
        let home = try model(day: 31)
        home.showNextMonth() // Kasım: 30 gün
        let row = try #require(home.rows.first)
        #expect(row.entry.dueDate.day == 30)
        #expect(row.installmentText == "2/3")
    }

    @Test("A user with no cards sees the installment total for the month")
    func monthTotal() throws {
        let home = try model(day: 5)
        #expect(home.total == Money(100))
    }
}
