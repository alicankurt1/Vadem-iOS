import Foundation
import Testing
import VademCore

@Suite("SubscriptionDraft")
struct SubscriptionDraftTests {
    private static let card = UUID()
    private static let october = YearMonth(year: 2026, month: 10)!

    private static func draft(
        title: String = "Müzik",
        card: UUID? = SubscriptionDraftTests.card,
        amount: Decimal? = 99,
        period: Subscription.Period = .monthly,
        day: Int = 5,
        month: YearMonth = SubscriptionDraftTests.october
    ) -> SubscriptionDraft {
        SubscriptionDraft(title: title, cardID: card, amount: amount, period: period, renewalDay: day, firstMonth: month)
    }

    @Test("A valid subscription has no errors and makes an item")
    func validDraft() throws {
        let draft = Self.draft(period: .yearly, day: 17)
        #expect(draft.errors.isEmpty)
        #expect(draft.isValid)
        let id = UUID()
        let item = try #require(draft.makeItem(id: id))
        #expect(item.id == id)
        #expect(item.title == "Müzik")
        #expect(item.cardID == Self.card)
        #expect(item.subscription.amount == Money(99))
        #expect(item.subscription.period == .yearly)
        #expect(item.subscription.renewalDay == 17)
        #expect(item.subscription.firstMonth == Self.october)
    }

    @Test("A subscription without a card is valid")
    func noCardIsValid() throws {
        let draft = Self.draft(card: nil)
        #expect(draft.isValid)
        #expect(try #require(draft.makeItem()).cardID == nil)
    }

    @Test("An unknown card id is not a draft error")
    func unknownCardIsNotChecked() {
        #expect(Self.draft(card: UUID()).isValid)
        #expect(Self.draft(card: UUID()).error(for: .card) == nil)
    }

    @Test("Title is validated after trimming", arguments: [
        ("", SubscriptionDraft.ValidationError.titleEmpty as SubscriptionDraft.ValidationError?),
        ("   ", .titleEmpty),
        ("\n\t ", .titleEmpty),
        ("a", nil),
        ("  Müzik  ", nil),
        (String(repeating: "a", count: 60), nil),
        (String(repeating: "a", count: 61), .titleTooLong),
        ("  " + String(repeating: "a", count: 60) + "  ", nil),
    ])
    func title(text: String, expected: SubscriptionDraft.ValidationError?) {
        #expect(Self.draft(title: text).error(for: .title) == expected)
    }

    @Test("Amount must be a number above zero kuruş", arguments: [
        (nil as Decimal?, SubscriptionDraft.ValidationError.amountMissing as SubscriptionDraft.ValidationError?),
        (0, .amountNotPositive),
        (-1, .amountNotPositive),
        (-0.01, .amountNotPositive),
        (0.004, .amountNotPositive),
        (0.005, nil),
        (0.01, nil),
        (149.90, nil),
        (999_999_999, nil),
    ])
    func amount(value: Decimal?, expected: SubscriptionDraft.ValidationError?) {
        #expect(Self.draft(amount: value).error(for: .amount) == expected)
    }

    @Test("Renewal day must be within 1 to 31", arguments: [
        (-1, false), (0, false), (1, true), (15, true), (28, true), (29, true), (30, true), (31, true), (32, false), (1000, false),
    ])
    func renewalDay(value: Int, isValid: Bool) {
        let error = Self.draft(day: value).error(for: .renewalDay)
        #expect((error == nil) == isValid)
        if !isValid { #expect(error == .renewalDayOutOfRange) }
    }

    @Test("Both periods are valid", arguments: [Subscription.Period.monthly, .yearly])
    func periods(period: Subscription.Period) {
        #expect(Self.draft(period: period).isValid)
    }

    @Test("Every month is a valid first month", arguments: [
        (2024, 2), (2026, 1), (2026, 12), (1999, 6),
    ])
    func firstMonth(year: Int, month: Int) throws {
        let value = try #require(YearMonth(year: year, month: month))
        #expect(Self.draft(month: value).error(for: .firstMonth) == nil)
        #expect(Self.draft(month: value).isValid)
    }

    @Test("An empty form breaks title and amount, in field order")
    func emptyDraft() {
        let draft = Self.draft(title: "", amount: nil)
        #expect(draft.errors == [.titleEmpty, .amountMissing])
        #expect(!draft.isValid)
        #expect(draft.makeItem() == nil)
    }

    @Test("Several broken rules are all reported, one per field")
    func allErrors() {
        let draft = Self.draft(title: " ", amount: -5, day: 40)
        #expect(draft.errors == [.titleEmpty, .amountNotPositive, .renewalDayOutOfRange])
        #expect(draft.makeItem() == nil)
    }

    @Test("Each error belongs to its field")
    func errorFields() {
        #expect(SubscriptionDraft.ValidationError.titleEmpty.field == .title)
        #expect(SubscriptionDraft.ValidationError.titleTooLong.field == .title)
        #expect(SubscriptionDraft.ValidationError.amountMissing.field == .amount)
        #expect(SubscriptionDraft.ValidationError.amountNotPositive.field == .amount)
        #expect(SubscriptionDraft.ValidationError.renewalDayOutOfRange.field == .renewalDay)
    }

    @Test("makeItem trims the title and rounds the amount to kuruş")
    func makeItemNormalizes() throws {
        let item = try #require(Self.draft(title: "  Bulut \n", amount: Decimal(string: "10.005")).makeItem())
        #expect(item.title == "Bulut")
        #expect(item.subscription.amount == Money(Decimal(string: "10.01")!))
    }
}
