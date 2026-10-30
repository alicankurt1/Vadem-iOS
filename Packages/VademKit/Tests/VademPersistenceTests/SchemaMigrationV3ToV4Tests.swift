import Foundation
import SwiftData
import Testing
import VademCore
@testable import VademPersistence
import VademTestSupport

// V3 ile gerçekten yazılmış bir dosya deposu, güncel şemayla (V4) açılınca hiçbir kaydı kaybetmez.
@MainActor
@Suite("Schema migration V3 to V4")
struct SchemaMigrationV3ToV4Tests {
    private static let card = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private static let phoneID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
    private static let musicID = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
    private static let taxID = UUID(uuidString: "00000000-0000-0000-0000-000000000014")!

    private static func writeV3Store(at url: URL) throws {
        let schema = Schema(versionedSchema: VademSchemaV3.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)
        context.insert(VademSchemaV3.CardRecord(id: card, name: "Bonus", statementDay: 5, dueDay: 15))
        context.insert(VademSchemaV3.InstallmentRecord(
            id: phoneID, title: "Telefon", cardID: card, paymentDay: nil, total: "1200.5", count: 6,
            firstYear: 2026, firstMonth: 11
        ))
        context.insert(VademSchemaV3.SubscriptionRecord(
            id: musicID, title: "Müzik", cardID: nil, amount: "49.99", period: "monthly", renewalDay: 31,
            firstYear: 2026, firstMonth: 3, lastYear: nil, lastMonth: nil
        ))
        context.insert(VademSchemaV3.OneTimePaymentRecord(
            id: taxID, title: "Vergi", cardID: card, amount: "250", dueYear: 2026, dueMonth: 12, dueDay: 31
        ))
        try context.save()
    }

    @Test("A V3 store keeps every record and starts with an empty inbox")
    func keepsEverything() throws {
        try TemporaryStore.with { url in
            try Self.writeV3Store(at: url)
            let container = try VademPersistence.makeContainer(storage: .file(url))
            let payments = SwiftDataPaymentRepository(container: container)

            #expect(try payments.cards().map(\.id) == [Self.card])
            #expect(try payments.cards().first?.name == "Bonus")
            let phone = try #require(try payments.installments().first)
            #expect(phone.id == Self.phoneID)
            #expect(phone.plan.total == Money(Decimal(string: "1200.5")!))
            #expect(phone.plan.count == 6)
            #expect(try payments.subscriptions().map(\.id) == [Self.musicID])
            let tax = try #require(try payments.oneTimePayments().first)
            #expect(tax.id == Self.taxID)
            #expect(tax.amount == Money(250))
            #expect(tax.dueDay == 31)

            let inbox = SwiftDataInboxRepository(container: container)
            #expect(try inbox.entries().isEmpty)
            #expect(try inbox.unreadCount() == 0)
        }
    }

    @Test("A migrated store saves inbox entries that survive a reopen next to the old records")
    func inboxWorksAfterMigration() throws {
        try TemporaryStore.with { url in
            try Self.writeV3Store(at: url)
            let entry = try Fixture.inboxEntry(.installmentEnded, createdAt: 5)
            do {
                let repo = try SwiftDataInboxRepository(container: VademPersistence.makeContainer(storage: .file(url)))
                try repo.add(entry)
            }
            let container = try VademPersistence.makeContainer(storage: .file(url))
            #expect(try SwiftDataInboxRepository(container: container).entries() == [entry])
            #expect(try SwiftDataPaymentRepository(container: container).cards().count == 1)
            #expect(try SwiftDataPaymentRepository(container: container).oneTimePayments().count == 1)
        }
    }
}
