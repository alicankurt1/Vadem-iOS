import Foundation
import Testing
import VademCore

@Suite("CardDraft")
struct CardDraftTests {
    private static let maxName = String(repeating: "a", count: Card.maxNameLength)

    struct Case: Sendable, CustomTestStringConvertible {
        let label: String
        let name: String
        let statement: Int?
        let due: Int?
        let expected: [CardDraft.ValidationError]
        var testDescription: String { label }
    }

    static let cases: [Case] = [
        Case(label: "valid card", name: "Bonus", statement: 10, due: 20, expected: []),
        Case(label: "empty name", name: "", statement: 10, due: 20, expected: [.nameEmpty]),
        Case(label: "whitespace-only name", name: "  \n ", statement: 10, due: 20, expected: [.nameEmpty]),
        Case(label: "name at the maximum", name: maxName, statement: 10, due: 20, expected: []),
        Case(label: "name over the maximum", name: maxName + "a", statement: 10, due: 20, expected: [.nameTooLong]),
        Case(label: "padding does not count toward the maximum", name: "  " + maxName + "  ", statement: 10, due: 20, expected: []),
        Case(label: "statement day 0", name: "Bonus", statement: 0, due: 20, expected: [.statementDayOutOfRange]),
        Case(label: "statement day 32", name: "Bonus", statement: 32, due: 20, expected: [.statementDayOutOfRange]),
        Case(label: "statement day negative", name: "Bonus", statement: -1, due: 20, expected: [.statementDayOutOfRange]),
        Case(label: "statement day missing", name: "Bonus", statement: nil, due: 20, expected: [.statementDayOutOfRange]),
        Case(label: "due day 0", name: "Bonus", statement: 10, due: 0, expected: [.dueDayOutOfRange]),
        Case(label: "due day 32", name: "Bonus", statement: 10, due: 32, expected: [.dueDayOutOfRange]),
        Case(label: "due day missing", name: "Bonus", statement: 10, due: nil, expected: [.dueDayOutOfRange]),
        Case(label: "days 1 and 31 are valid", name: "Bonus", statement: 1, due: 31, expected: []),
        Case(label: "everything wrong", name: " ", statement: 0, due: 99,
             expected: [.nameEmpty, .statementDayOutOfRange, .dueDayOutOfRange]),
    ]

    @Test("Reports the broken rules in field order", arguments: cases)
    func errors(_ c: Case) {
        let draft = CardDraft(name: c.name, statementDay: c.statement, dueDay: c.due)
        #expect(draft.errors == c.expected)
        #expect(draft.isValid == c.expected.isEmpty)
    }

    @Test("makeCard returns a trimmed card only for a valid draft", arguments: cases)
    func makeCard(_ c: Case) {
        let card = CardDraft(name: c.name, statementDay: c.statement, dueDay: c.due).makeCard()
        #expect((card != nil) == c.expected.isEmpty)
    }

    @Test("makeCard trims the name and keeps id and days")
    func makeCardValues() throws {
        let id = UUID()
        let card = try #require(CardDraft(name: "  Bonus \n", statementDay: 5, dueDay: 15).makeCard(id: id))
        #expect(card.id == id)
        #expect(card.name == "Bonus")
        #expect(card.statementDay == 5)
        #expect(card.dueDay == 15)
    }

    @Test("Each error belongs to its field", arguments: [
        (CardDraft.ValidationError.nameEmpty, CardDraft.Field.name),
        (.nameTooLong, .name),
        (.statementDayOutOfRange, .statementDay),
        (.dueDayOutOfRange, .dueDay),
    ])
    func fieldOfError(_ pair: (CardDraft.ValidationError, CardDraft.Field)) {
        #expect(pair.0.field == pair.1)
    }

    @Test("error(for:) returns only the error of that field")
    func errorForField() {
        let draft = CardDraft(name: "Bonus", statementDay: 40, dueDay: 10)
        #expect(draft.error(for: .name) == nil)
        #expect(draft.error(for: .statementDay) == .statementDayOutOfRange)
        #expect(draft.error(for: .dueDay) == nil)
    }
}
