import Foundation
import Testing
import VademCore

@Suite("OneTimePaymentDraft")
struct OneTimePaymentDraftTests {
    private static let card = UUID()
    private static let june = YearMonth(year: 2026, month: 6)!

    private static func draft(
        title: String = "Vergi",
        card: UUID? = OneTimePaymentDraftTests.card,
        amount: Decimal? = 250,
        month: YearMonth = OneTimePaymentDraftTests.june,
        day: Int = 15
    ) -> OneTimePaymentDraft {
        OneTimePaymentDraft(title: title, cardID: card, amount: amount, dueMonth: month, dueDay: day)
    }

    @Test("A valid draft has no errors and makes an item")
    func validDraft() throws {
        let draft = Self.draft(title: "  Vergi  ", amount: Decimal(string: "250.50")!)
        #expect(draft.errors.isEmpty)
        #expect(draft.isValid)
        let id = UUID()
        let item = try #require(draft.makeItem(id: id))
        #expect(item.id == id)
        #expect(item.title == "Vergi")
        #expect(item.cardID == Self.card)
        #expect(item.amount == Money(Decimal(string: "250.50")!))
        #expect(item.dueMonth == Self.june)
        #expect(item.dueDay == 15)
    }

    @Test("A draft without a card is valid")
    func noCardIsValid() throws {
        let item = try #require(Self.draft(card: nil).makeItem())
        #expect(item.cardID == nil)
    }

    @Test("Empty or whitespace titles are rejected", arguments: ["", "   ", "\n\t "])
    func emptyTitle(title: String) {
        let draft = Self.draft(title: title)
        #expect(draft.errors == [.titleEmpty])
        #expect(draft.error(for: .title) == .titleEmpty)
        #expect(draft.makeItem() == nil)
    }

    @Test("Title length limit is 60 after trimming", arguments: [(60, true), (61, false)])
    func titleLength(count: Int, valid: Bool) {
        let draft = Self.draft(title: "  " + String(repeating: "a", count: count) + "  ")
        #expect(draft.isValid == valid)
        #expect(draft.error(for: .title) == (valid ? nil : .titleTooLong))
    }

    @Test("A missing amount is rejected")
    func missingAmount() {
        let draft = Self.draft(amount: nil)
        #expect(draft.errors == [.amountMissing])
        #expect(draft.error(for: .amount) == .amountMissing)
        #expect(draft.makeItem() == nil)
    }

    @Test("Zero, negative and amounts that round to zero are rejected",
          arguments: ["0", "-1", "-0.01", "0.004", "0.001"])
    func nonPositiveAmount(text: String) {
        let draft = Self.draft(amount: Decimal(string: text)!)
        #expect(draft.errors == [.amountNotPositive])
        #expect(draft.makeItem() == nil)
    }

    @Test("Amounts at the kuruş boundary", arguments: [("0.005", true), ("0.01", true), ("0.0049", false)])
    func kurusBoundary(text: String, valid: Bool) {
        // 0,005 yarıdan yukarı yuvarlanır: 0,01 olur ve geçerlidir.
        #expect(Self.draft(amount: Decimal(string: text)!).isValid == valid)
    }

    @Test("A very large amount is accepted")
    func largeAmount() throws {
        let item = try #require(Self.draft(amount: Decimal(string: "999999999.99")!).makeItem())
        #expect(item.amount == Money(Decimal(string: "999999999.99")!))
    }

    @Test("Due day must be a day of the due month",
          arguments: [
              (2026, 2, 28, true), (2026, 2, 29, false), (2028, 2, 29, true), (2028, 2, 30, false),
              (2026, 4, 30, true), (2026, 4, 31, false), (2026, 1, 31, true), (2026, 1, 1, true),
              (2026, 1, 0, false), (2026, 1, -1, false), (2026, 12, 32, false),
          ])
    func dueDay(year: Int, month: Int, day: Int, valid: Bool) {
        let draft = Self.draft(month: YearMonth(year: year, month: month)!, day: day)
        #expect(draft.isValid == valid)
        #expect(draft.error(for: .dueDate) == (valid ? nil : .dueDayOutOfRange))
        #expect((draft.makeItem() != nil) == valid)
    }

    @Test("Every broken field reports its own error")
    func allErrors() {
        let draft = Self.draft(title: " ", amount: nil, day: 0)
        #expect(Set(draft.errors) == [.titleEmpty, .amountMissing, .dueDayOutOfRange])
        #expect(draft.error(for: .card) == nil)
        #expect(draft.makeItem() == nil)
    }
}

@Suite("OneTimePaymentItem")
struct OneTimePaymentItemTests {
    private static let june = YearMonth(year: 2026, month: 6)!

    @Test("The initializer rejects invalid values")
    func rejects() {
        #expect(OneTimePaymentItem(title: "", cardID: nil, amount: Money(10), dueMonth: Self.june, dueDay: 1) == nil)
        #expect(OneTimePaymentItem(title: "A", cardID: nil, amount: .zero, dueMonth: Self.june, dueDay: 1) == nil)
        #expect(OneTimePaymentItem(title: "A", cardID: nil, amount: Money(-5), dueMonth: Self.june, dueDay: 1) == nil)
        #expect(OneTimePaymentItem(title: "A", cardID: nil, amount: Money(5), dueMonth: Self.june, dueDay: 31) == nil)
        #expect(OneTimePaymentItem(title: "A", cardID: nil, amount: Money(5), dueMonth: Self.june, dueDay: 0) == nil)
    }

    @Test("Codable round trip keeps all values, with and without a card", arguments: [true, false])
    func roundTrip(withCard: Bool) throws {
        let item = try #require(OneTimePaymentItem(
            title: "Vergi", cardID: withCard ? UUID() : nil, amount: Money(Decimal(string: "12.34")!),
            dueMonth: Self.june, dueDay: 30
        ))
        let data = try JSONEncoder().encode(item)
        #expect(try JSONDecoder().decode(OneTimePaymentItem.self, from: data) == item)
    }

    @Test("Decoding an invalid item fails")
    func decodeInvalid() throws {
        let item = try #require(OneTimePaymentItem(
            title: "Vergi", cardID: nil, amount: Money(10), dueMonth: Self.june, dueDay: 30
        ))
        var json = try #require(String(data: JSONEncoder().encode(item), encoding: .utf8))
        json = json.replacingOccurrences(of: "\"dueDay\":30", with: "\"dueDay\":31")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(OneTimePaymentItem.self, from: Data(json.utf8))
        }
    }
}
