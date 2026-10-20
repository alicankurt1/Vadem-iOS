import Foundation
import Testing
import VademCore
import VademTestSupport

@Suite("SubscriptionItem")
struct SubscriptionItemTests {
    @Test("Conforms to Sendable, Hashable, Codable and Identifiable with a UUID id")
    func conformances() {
        #expect(requiresItemConformances(SubscriptionItem.self))
    }

    @Test("Keeps every value it was created with, with or without a card", arguments: [true, false])
    func storesValues(withCard: Bool) throws {
        let id = Fixture.id(1)
        let cardID: Card.ID? = withCard ? Fixture.id(2) : nil
        let subscription = try Fixture.subscription(amount: 1299, period: .yearly)
        let item = try #require(SubscriptionItem(id: id, title: "Bulut", cardID: cardID, subscription: subscription))
        #expect(item.id == id)
        #expect(item.title == "Bulut")
        #expect(item.cardID == cardID)
        #expect(item.subscription == subscription)
    }

    @Test("A new UUID is generated when no id is given")
    func defaultID() throws {
        let subscription = try Fixture.subscription()
        let first = try #require(SubscriptionItem(title: "Müzik", cardID: nil, subscription: subscription))
        let second = try #require(SubscriptionItem(title: "Müzik", cardID: nil, subscription: subscription))
        #expect(first.id != second.id)
    }

    @Test(
        "Trims the title",
        arguments: [
            ("  Müzik  ", "Müzik"),
            ("\tVideo\n", "Video"),
            (" Spor salonu ", "Spor salonu"),
        ]
    )
    func trimsTitle(input: String, expected: String) throws {
        let item = try #require(SubscriptionItem(title: input, cardID: nil, subscription: try Fixture.subscription()))
        #expect(item.title == expected)
    }

    @Test(
        "Rejects a title that is empty after trimming or longer than 60 characters",
        arguments: [
            "",
            " ",
            "\n\t  ",
            String(repeating: "a", count: 61),
            String(repeating: "ü", count: 61),
        ]
    )
    func rejectsInvalidTitle(title: String) throws {
        #expect(SubscriptionItem(title: title, cardID: Fixture.id(1), subscription: try Fixture.subscription()) == nil)
        #expect(SubscriptionItem(title: title, cardID: nil, subscription: try Fixture.subscription()) == nil)
    }

    @Test(
        "Accepts titles of 1 to 60 characters, counted after trimming",
        arguments: [
            "a",
            String(repeating: "a", count: 60),
            "  " + String(repeating: "ç", count: 60) + "  ",
        ]
    )
    func acceptsBoundaryTitles(title: String) throws {
        let item = try #require(SubscriptionItem(title: title, cardID: nil, subscription: try Fixture.subscription()))
        #expect(item.title.count <= 60)
        #expect(!item.title.isEmpty)
    }

    @Test("Items with the same values are equal; a different id makes them different")
    func hashable() throws {
        let subscription = try Fixture.subscription()
        let a = try Fixture.subscriptionItem("Müzik", id: Fixture.id(1), card: nil, subscription: subscription)
        let b = try Fixture.subscriptionItem("Müzik", id: Fixture.id(1), card: nil, subscription: subscription)
        let c = try Fixture.subscriptionItem("Müzik", id: Fixture.id(2), card: nil, subscription: subscription)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(a != c)
        #expect(Set([a, b, c]).count == 2)
    }

    @Test("Round-trips exactly through JSON, including id and an optional card", arguments: [true, false])
    func codableRoundTrip(withCard: Bool) throws {
        let original = try Fixture.subscriptionItem(
            "Video", id: Fixture.id(7), card: withCard ? Fixture.id(8) : nil,
            subscription: try Fixture.subscription(amount: Decimal(string: "149.99")!, period: .monthly)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SubscriptionItem.self, from: data)
        #expect(decoded == original)
        #expect(decoded.cardID == (withCard ? Fixture.id(8) : nil))
    }

    @Test(
        "Decoding rejects an invalid title",
        arguments: ["", "   ", String(repeating: "a", count: 61)]
    )
    func decodingRejectsInvalidTitle(title: String) throws {
        let valid = try Fixture.subscriptionItem(card: nil)
        #expect(throws: (any Error).self) {
            _ = try decodeAfterReplacing("title", with: title, in: valid)
        }
    }

    @Test("Decoding trims the title like the initializer")
    func decodingTrimsTitle() throws {
        let valid = try Fixture.subscriptionItem(card: Fixture.id(1))
        let decoded = try decodeAfterReplacing("title", with: " Haber \t", in: valid)
        #expect(decoded.title == "Haber")
    }
}
