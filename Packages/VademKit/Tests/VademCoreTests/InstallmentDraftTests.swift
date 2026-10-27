import Foundation
import Testing
import VademCore

@Suite("InstallmentDraft")
struct InstallmentDraftTests {
    private static let card = UUID()
    private static let october = YearMonth(year: 2026, month: 10)!

    private static func draft(
        title: String = "Telefon",
        card: UUID? = InstallmentDraftTests.card,
        paymentDay: Int = 15,
        total: Decimal? = 1200,
        count: Int = 3,
        month: YearMonth = InstallmentDraftTests.october
    ) -> InstallmentDraft {
        InstallmentDraft(title: title, cardID: card, paymentDay: paymentDay, total: total, count: count, firstMonth: month)
    }

    @Test("A valid plan has no errors and makes an item")
    func validPlan() throws {
        let draft = Self.draft()
        #expect(draft.errors.isEmpty)
        #expect(draft.isValid)
        let item = try #require(draft.makeItem(id: Fixture0.id))
        #expect(item.title == "Telefon")
        #expect(item.cardID == Self.card)
        #expect(item.plan.total == Money(1200))
        #expect(item.plan.count == 3)
        #expect(item.plan.firstMonth == Self.october)
    }

    @Test("Title is validated after trimming", arguments: [
        ("", InstallmentDraft.ValidationError.titleEmpty as InstallmentDraft.ValidationError?),
        ("   ", .titleEmpty),
        ("\n\t ", .titleEmpty),
        ("a", nil),
        ("  Telefon  ", nil),
        (String(repeating: "a", count: 60), nil),
        (String(repeating: "a", count: 61), .titleTooLong),
        ("  " + String(repeating: "a", count: 60) + "  ", nil),
    ])
    func title(text: String, expected: InstallmentDraft.ValidationError?) {
        #expect(Self.draft(title: text).error(for: .title) == expected)
    }

    @Test("Amount must be a number above zero kuruş", arguments: [
        (nil as Decimal?, InstallmentDraft.ValidationError.amountMissing as InstallmentDraft.ValidationError?),
        (0, .amountNotPositive),
        (-1, .amountNotPositive),
        (-0.01, .amountNotPositive),
        (0.004, .amountNotPositive),
        (0.005, nil),
        (0.01, nil),
        (1200, nil),
        (999_999_999, nil),
    ])
    func amount(total: Decimal?, expected: InstallmentDraft.ValidationError?) {
        #expect(Self.draft(total: total).error(for: .amount) == expected)
    }

    @Test("Count must be within 1 to 36", arguments: [
        (-1, false), (0, false), (1, true), (2, true), (12, true), (36, true), (37, false), (1000, false),
    ])
    func count(value: Int, isValid: Bool) {
        let error = Self.draft(count: value).error(for: .count)
        #expect((error == nil) == isValid)
        if !isValid { #expect(error == .countOutOfRange) }
    }

    @Test("Without a card a valid payment day is enough")
    func cardLessValid() throws {
        let draft = Self.draft(card: nil, paymentDay: 20)
        #expect(draft.errors.isEmpty)
        let item = try #require(draft.makeItem())
        #expect(item.cardID == nil)
        #expect(item.paymentDay == 20)
    }

    @Test("Without a card the payment day must be 1 to 31", arguments: [
        (-5, false), (0, false), (1, true), (15, true), (28, true), (29, true), (30, true), (31, true),
        (32, false), (100, false),
    ])
    func paymentDayWithoutCard(day: Int, isValid: Bool) {
        let draft = Self.draft(card: nil, paymentDay: day)
        #expect((draft.error(for: .paymentDay) == nil) == isValid)
        if !isValid { #expect(draft.error(for: .paymentDay) == .paymentDayOutOfRange) }
        #expect(draft.isValid == isValid)
        #expect((draft.makeItem() != nil) == isValid)
    }

    @Test("With a card the payment day is ignored and not stored", arguments: [0, 15, 99, -1])
    func paymentDayIgnoredWithCard(day: Int) throws {
        let draft = Self.draft(paymentDay: day)
        #expect(draft.error(for: .paymentDay) == nil)
        #expect(draft.isValid)
        let item = try #require(draft.makeItem())
        #expect(item.cardID == Self.card)
        #expect(item.paymentDay == nil)
    }

    @Test("A card-less draft still enforces the other rules")
    func cardLessOtherRules() {
        #expect(Self.draft(title: " ", card: nil).error(for: .title) == .titleEmpty)
        #expect(Self.draft(card: nil, total: 0).makeItem() == nil)
        #expect(Self.draft(card: nil, count: 0).makeItem() == nil)
    }

    @Test("The last payment may not pass December 9999", arguments: [
        (9999, 12, 1, true),
        (9999, 12, 2, false),
        (9999, 11, 2, true),
        (9999, 11, 3, false),
        (9998, 12, 13, true),
        (9998, 12, 14, false),
        (9999, 1, 12, true),
        (9999, 1, 13, false),
    ])
    func firstMonthRange(year: Int, month: Int, count: Int, isValid: Bool) throws {
        let first = try #require(YearMonth(year: year, month: month))
        let error = Self.draft(count: count, month: first).error(for: .firstMonth)
        #expect((error == nil) == isValid)
    }

    @Test("Every broken rule is listed, in field order, one per field")
    func allErrors() {
        let draft = Self.draft(title: " ", card: nil, paymentDay: 0, total: nil, count: 0)
        #expect(draft.errors == [.titleEmpty, .paymentDayOutOfRange, .amountMissing, .countOutOfRange])
        #expect(draft.makeItem() == nil)
        #expect(Set(draft.errors.map(\.field)).count == draft.errors.count)
    }

    @Test("Each error belongs to its field", arguments: [
        (InstallmentDraft.ValidationError.titleEmpty, InstallmentDraft.Field.title),
        (.titleTooLong, .title),
        (.paymentDayOutOfRange, .paymentDay),
        (.amountMissing, .amount),
        (.amountNotPositive, .amount),
        (.countOutOfRange, .count),
        (.firstMonthOutOfRange, .firstMonth),
    ])
    func fieldMapping(error: InstallmentDraft.ValidationError, field: InstallmentDraft.Field) {
        #expect(error.field == field)
    }

    @Test("The made item has a trimmed title and the given id")
    func trimmedTitleAndID() throws {
        let id = UUID()
        let item = try #require(Self.draft(title: "  Telefon \n").makeItem(id: id))
        #expect(item.title == "Telefon")
        #expect(item.id == id)
    }

    @Test("The amount is rounded to kuruş when the item is made")
    func roundsToKurus() throws {
        let item = try #require(Self.draft(total: Decimal(string: "10.005")!).makeItem())
        #expect(item.plan.total == Money(Decimal(string: "10.01")!))
    }
}

private enum Fixture0 {
    static let id = UUID()
}
