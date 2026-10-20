import Foundation
import Testing
import VademCore

@Suite("InstallmentItem")
struct InstallmentItemTests {
    @Test("Conforms to Sendable, Hashable, Codable and Identifiable with a UUID id")
    func conformances() {
        #expect(requiresItemConformances(InstallmentItem.self))
    }

    @Test("Keeps every value it was created with")
    func storesValues() throws {
        let id = Fixture.id(1)
        let cardID = Fixture.id(2)
        let plan = try Fixture.plan(total: 3000, count: 6)
        let item = try #require(InstallmentItem(id: id, title: "Laptop", cardID: cardID, plan: plan))
        #expect(item.id == id)
        #expect(item.title == "Laptop")
        #expect(item.cardID == cardID)
        #expect(item.plan == plan)
    }

    @Test("A new UUID is generated when no id is given")
    func defaultID() throws {
        let plan = try Fixture.plan()
        let first = try #require(InstallmentItem(title: "Telefon", cardID: Fixture.id(1), plan: plan))
        let second = try #require(InstallmentItem(title: "Telefon", cardID: Fixture.id(1), plan: plan))
        #expect(first.id != second.id)
    }

    @Test(
        "Trims the title",
        arguments: [
            ("  Telefon  ", "Telefon"),
            ("\tKoltuk\n", "Koltuk"),
            ("Beyaz eşya", "Beyaz eşya"),
            (" iç boşluk korunur ", "iç boşluk korunur"),
        ]
    )
    func trimsTitle(input: String, expected: String) throws {
        let item = try #require(InstallmentItem(title: input, cardID: Fixture.id(1), plan: try Fixture.plan()))
        #expect(item.title == expected)
    }

    @Test(
        "Rejects a title that is empty after trimming or longer than 60 characters",
        arguments: [
            "",
            " ",
            "\n\t  ",
            String(repeating: "a", count: 61),
            String(repeating: "ş", count: 61),
            String(repeating: "x", count: 200),
        ]
    )
    func rejectsInvalidTitle(title: String) throws {
        #expect(InstallmentItem(title: title, cardID: Fixture.id(1), plan: try Fixture.plan()) == nil)
    }

    @Test(
        "Accepts titles of 1 to 60 characters, counted after trimming",
        arguments: [
            "a",
            String(repeating: "a", count: 60),
            String(repeating: "ğ", count: 60),
            "   " + String(repeating: "b", count: 60) + "   ",
        ]
    )
    func acceptsBoundaryTitles(title: String) throws {
        let item = try #require(InstallmentItem(title: title, cardID: Fixture.id(1), plan: try Fixture.plan()))
        #expect(item.title.count <= 60)
        #expect(!item.title.isEmpty)
    }

    @Test("Items with the same values are equal; a different id makes them different")
    func hashable() throws {
        let plan = try Fixture.plan()
        let a = try Fixture.installment("Telefon", id: Fixture.id(1), card: Fixture.id(9), plan: plan)
        let b = try Fixture.installment("Telefon", id: Fixture.id(1), card: Fixture.id(9), plan: plan)
        let c = try Fixture.installment("Telefon", id: Fixture.id(2), card: Fixture.id(9), plan: plan)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(a != c)
        #expect(Set([a, b, c]).count == 2)
    }

    @Test("Round-trips exactly through JSON, including id")
    func codableRoundTrip() throws {
        let original = try Fixture.installment(
            "Buzdolabı", id: Fixture.id(7), card: Fixture.id(8),
            plan: try Fixture.plan(total: Decimal(string: "1000.01")!, count: 3, first: Fixture.month(2026, 11))
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InstallmentItem.self, from: data)
        #expect(decoded == original)
        #expect(decoded.id == Fixture.id(7))
    }

    @Test(
        "Decoding rejects an invalid title",
        arguments: ["", "   ", String(repeating: "a", count: 61)]
    )
    func decodingRejectsInvalidTitle(title: String) throws {
        let valid = try Fixture.installment(card: Fixture.id(1))
        #expect(throws: (any Error).self) {
            _ = try decodeAfterReplacing("title", with: title, in: valid)
        }
    }

    @Test("Decoding trims the title like the initializer")
    func decodingTrimsTitle() throws {
        let valid = try Fixture.installment(card: Fixture.id(1))
        let decoded = try decodeAfterReplacing("title", with: "  Kulaklık \n", in: valid)
        #expect(decoded.title == "Kulaklık")
    }

    @Test("Decoding accepts a 60-character title")
    func decodingAcceptsMaxTitle() throws {
        let valid = try Fixture.installment(card: Fixture.id(1))
        let title = String(repeating: "z", count: 60)
        let decoded = try decodeAfterReplacing("title", with: title, in: valid)
        #expect(decoded.title == title)
    }
}
