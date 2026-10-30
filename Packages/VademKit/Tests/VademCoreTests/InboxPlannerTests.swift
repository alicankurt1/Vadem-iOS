import Foundation
import Testing
import VademCore
import VademTestSupport

@Suite("InboxPlanner and InboxEntry")
struct InboxPlannerTests {
    private static let created = Date(timeIntervalSinceReferenceDate: 1000)

    private static func rent(_ amount: Decimal, from first: YearMonth) throws -> SubscriptionItem {
        let value = try #require(Subscription(amount: Money(amount), period: .monthly, renewalDay: 5, firstMonth: first))
        return try #require(SubscriptionItem(id: UUID(), title: "Rent", cardID: nil, subscription: value))
    }

    private static func entries(
        _ month: YearMonth, subs: [SubscriptionItem], installments: [InstallmentItem] = []
    ) -> [InboxEntry] {
        InboxPlanner.entries(
            for: month, createdAt: created, cards: [], installments: installments, subscriptions: subs
        ) { insight in
            InboxPlanner.Text(title: "T-\(insight.kind.rawValue)", body: "B-\(insight.id)")
        }
    }

    @Test("Every insight becomes one unread entry, most important first")
    func oneEntryPerInsight() throws {
        let jan = try Fixture.month(2026, 1)
        // Ekim: 5000 + 1000 (son taksit) = 6000; Kasım: 5000 + 3000 = 8000 -> +%33 ve biten taksit.
        let result = Self.entries(
            try Fixture.month(2026, 11),
            subs: [try Self.rent(5000, from: jan), try Self.rent(3000, from: try Fixture.month(2026, 11))],
            installments: [try Fixture.installment(
                "Phone", card: nil, plan: Fixture.plan(total: 3000, count: 3, first: try Fixture.month(2026, 8))
            )]
        )
        #expect(result.map(\.id) == ["insight-2026-11-totalChange", "insight-2026-11-installmentEnded"])
        #expect(result.map(\.kind) == [.totalChange, .installmentEnded])
        #expect(result.allSatisfy { !$0.isRead })
        #expect(result.allSatisfy { $0.createdAt == Self.created })
        #expect(result.allSatisfy { $0.month == (try? Fixture.month(2026, 11)) })
        #expect(result.first?.title == "T-totalChange")
        #expect(result.first?.body == "B-insight-2026-11-totalChange")
    }

    @Test("A month without insights gives no entries")
    func noInsights() throws {
        let jan = try Fixture.month(2026, 1)
        #expect(Self.entries(try Fixture.month(2026, 11), subs: [try Self.rent(5000, from: jan)]).isEmpty)
        #expect(Self.entries(try Fixture.month(2026, 11), subs: []).isEmpty)
    }

    @Test("Planning twice gives the same ids")
    func idsAreStable() throws {
        let subs = [try Self.rent(1000, from: try Fixture.month(2026, 1)), try Self.rent(1000, from: try Fixture.month(2026, 11))]
        let first = Self.entries(try Fixture.month(2026, 11), subs: subs)
        let second = Self.entries(try Fixture.month(2026, 11), subs: subs)
        #expect(!first.isEmpty)
        #expect(first.map(\.id) == second.map(\.id))
    }

    @Test("A new entry from an insight is unread by default")
    func newEntryIsUnread() throws {
        let entry = try Fixture.inboxEntry()
        #expect(!entry.isRead)
    }

    @Test("Ordering: newer createdAt first, then newer month, then importance, then id")
    func ordering() throws {
        let newer = try Fixture.inboxEntry(.installmentEnded, month: Fixture.month(2026, 1), createdAt: 2)
        let older = try Fixture.inboxEntry(.totalChange, month: Fixture.month(2026, 12), createdAt: 1)
        #expect(InboxEntry.isOrdered(newer, before: older))
        #expect(!InboxEntry.isOrdered(older, before: newer))

        let laterMonth = try Fixture.inboxEntry(.installmentEnded, month: Fixture.month(2026, 12), createdAt: 1)
        let earlierMonth = try Fixture.inboxEntry(.totalChange, month: Fixture.month(2026, 11), createdAt: 1)
        #expect(InboxEntry.isOrdered(laterMonth, before: earlierMonth))

        let important = try Fixture.inboxEntry(.totalChange, createdAt: 1)
        let minor = try Fixture.inboxEntry(.installmentEnded, createdAt: 1)
        #expect(InboxEntry.isOrdered(important, before: minor))
        #expect(!InboxEntry.isOrdered(important, before: important))
    }
}

@Suite("NotificationRoute")
struct NotificationRouteTests {
    @Test("Routes by notification identifier", arguments: [
        ("insight-2026-11", NotificationRoute?.some(.inbox)),
        ("insight-2026-11-totalChange", .some(.inbox)),
        ("insight-", .some(.inbox)),
        ("due-2026-11-15", nil),
        ("", nil),
        ("Insight-2026-11", nil),
        ("my-insight-2026-11", nil),
    ])
    func routes(identifier: String, expected: NotificationRoute?) {
        #expect(NotificationRoute.route(forNotificationIdentifier: identifier) == expected)
    }
}
