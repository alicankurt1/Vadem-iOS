import Foundation
import SwiftData
import Testing
import VademCore
@testable import VademPersistence
import VademTestSupport

// V1 ile gerçekten yazılmış bir dosya deposu, güncel şemayla açılınca (göç) hiçbir kaydı kaybetmez.
@MainActor
@Suite("Schema migration V1 to V2")
struct SchemaMigrationTests {
    private static let cardA = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private static let cardB = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
    private static let phoneID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
    private static let sofaID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
    private static let musicID = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!

    /// Depoyu yalnızca V1 şemasıyla (göç planı olmadan) oluşturur ve yazar; kap sonunda serbest kalır.
    private static func writeV1Store(at url: URL) throws {
        let schema = Schema(versionedSchema: VademSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)
        context.insert(VademSchemaV1.CardRecord(id: cardA, name: "Bonus", statementDay: 5, dueDay: 15))
        context.insert(VademSchemaV1.CardRecord(id: cardB, name: "Axess", statementDay: 31, dueDay: 10))
        context.insert(VademSchemaV1.InstallmentRecord(
            id: phoneID, title: "Telefon", cardID: cardA, total: "1200.5", count: 6, firstYear: 2026, firstMonth: 11
        ))
        context.insert(VademSchemaV1.InstallmentRecord(
            id: sofaID, title: "Koltuk", cardID: cardB, total: "9000", count: 12, firstYear: 2026, firstMonth: 1
        ))
        context.insert(VademSchemaV1.SubscriptionRecord(
            id: musicID, title: "Müzik", cardID: nil, amount: "49.99", period: "monthly", renewalDay: 31,
            firstYear: 2026, firstMonth: 3, lastYear: nil, lastMonth: nil
        ))
        try context.save()
    }

    @Test("A V1 store keeps all cards, installments and subscriptions after migration")
    func keepsEverything() throws {
        try TemporaryStore.with { url in
            try Self.writeV1Store(at: url)
            let repository = try SwiftDataPaymentRepository(
                container: VademPersistence.makeContainer(storage: .file(url))
            )

            let cards = try repository.cards()
            #expect(cards.map(\.id) == [Self.cardB, Self.cardA]) // Axess, Bonus
            #expect(cards.first { $0.id == Self.cardA }?.name == "Bonus")
            #expect(cards.first { $0.id == Self.cardA }?.statementDay == 5)
            #expect(cards.first { $0.id == Self.cardA }?.dueDay == 15)
            #expect(cards.first { $0.id == Self.cardB }?.statementDay == 31)

            let installments = try repository.installments()
            #expect(installments.count == 2)
            let phone = try #require(installments.first { $0.id == Self.phoneID })
            #expect(phone.title == "Telefon")
            #expect(phone.cardID == Self.cardA)
            #expect(phone.paymentDay == nil)
            #expect(phone.plan.total == Money(Decimal(string: "1200.5")!))
            #expect(phone.plan.count == 6)
            #expect(phone.plan.firstMonth == YearMonth(year: 2026, month: 11))
            let sofa = try #require(installments.first { $0.id == Self.sofaID })
            #expect(sofa.cardID == Self.cardB)
            #expect(sofa.paymentDay == nil)
            #expect(sofa.plan.total == Money(9000))
            #expect(sofa.plan.count == 12)

            let subscriptions = try repository.subscriptions()
            #expect(subscriptions.map(\.id) == [Self.musicID])
            #expect(subscriptions.first?.cardID == nil)
            #expect(subscriptions.first?.subscription.renewalDay == 31)
        }
    }

    @Test("Migrated cards are still protected from deletion while installments use them")
    func migratedLinksStillWork() throws {
        try TemporaryStore.with { url in
            try Self.writeV1Store(at: url)
            let repository = try SwiftDataPaymentRepository(
                container: VademPersistence.makeContainer(storage: .file(url))
            )
            #expect(throws: RepositoryError.cardInUse) { try repository.deleteCard(id: Self.cardA) }
        }
    }

    @Test("A migrated store accepts card-less installments next to migrated ones")
    func newCardlessAfterMigration() throws {
        try TemporaryStore.with { url in
            try Self.writeV1Store(at: url)
            let cardless = try Fixture.installment("Okul", id: Fixture.id(50), card: nil, paymentDay: 29)
            do {
                let repository = try SwiftDataPaymentRepository(
                    container: VademPersistence.makeContainer(storage: .file(url))
                )
                try repository.save(cardless)
            }
            let reopened = try SwiftDataPaymentRepository(
                container: VademPersistence.makeContainer(storage: .file(url))
            )
            let installments = try reopened.installments()
            #expect(installments.count == 3)
            #expect(installments.contains(cardless))
            #expect(try reopened.cards().count == 2)
        }
    }
}

// V2 ile gerçekten yazılmış bir dosya deposu, güncel şemayla (V3) açılınca hiçbir kaydı kaybetmez.
@MainActor
@Suite("Schema migration V2 to V3")
struct SchemaMigrationV2ToV3Tests {
    private static let card = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private static let phoneID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
    private static let rentID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
    private static let musicID = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!

    private static func writeV2Store(at url: URL) throws {
        let schema = Schema(versionedSchema: VademSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)
        context.insert(VademSchemaV2.CardRecord(id: card, name: "Bonus", statementDay: 5, dueDay: 15))
        context.insert(VademSchemaV2.InstallmentRecord(
            id: phoneID, title: "Telefon", cardID: card, paymentDay: nil, total: "1200.5", count: 6,
            firstYear: 2026, firstMonth: 11
        ))
        context.insert(VademSchemaV2.InstallmentRecord(
            id: rentID, title: "Kira", cardID: nil, paymentDay: 29, total: "900", count: 3,
            firstYear: 2026, firstMonth: 1
        ))
        context.insert(VademSchemaV2.SubscriptionRecord(
            id: musicID, title: "Müzik", cardID: nil, amount: "49.99", period: "monthly", renewalDay: 31,
            firstYear: 2026, firstMonth: 3, lastYear: nil, lastMonth: nil
        ))
        try context.save()
    }

    @Test("A V2 store keeps everything and starts with no one-time payments")
    func keepsEverything() throws {
        try TemporaryStore.with { url in
            try Self.writeV2Store(at: url)
            let repository = try SwiftDataPaymentRepository(
                container: VademPersistence.makeContainer(storage: .file(url))
            )
            let cards = try repository.cards()
            #expect(cards.map(\.id) == [Self.card])
            #expect(cards.first?.name == "Bonus")
            #expect(cards.first?.statementDay == 5)

            let installments = try repository.installments()
            #expect(installments.count == 2)
            let phone = try #require(installments.first { $0.id == Self.phoneID })
            #expect(phone.cardID == Self.card)
            #expect(phone.plan.total == Money(Decimal(string: "1200.5")!))
            let rent = try #require(installments.first { $0.id == Self.rentID })
            #expect(rent.cardID == nil)
            #expect(rent.paymentDay == 29)

            let subscriptions = try repository.subscriptions()
            #expect(subscriptions.map(\.id) == [Self.musicID])
            #expect(subscriptions.first?.subscription.renewalDay == 31)

            #expect(try repository.oneTimePayments().isEmpty)
        }
    }

    @Test("A migrated store saves one-time payments that survive a reopen and protect their card")
    func newPaymentsAfterMigration() throws {
        try TemporaryStore.with { url in
            try Self.writeV2Store(at: url)
            let withCard = try Fixture.oneTimePayment("Vergi", id: Fixture.id(60), card: Self.card, due: Fixture.month(2026, 12), day: 31)
            let cardless = try Fixture.oneTimePayment("Harç", id: Fixture.id(61), card: nil, amount: Decimal(string: "10.05")!)
            do {
                let repository = try SwiftDataPaymentRepository(
                    container: VademPersistence.makeContainer(storage: .file(url))
                )
                try repository.save(withCard)
                try repository.save(cardless)
            }
            let reopened = try SwiftDataPaymentRepository(
                container: VademPersistence.makeContainer(storage: .file(url))
            )
            #expect(try reopened.oneTimePayments() == [cardless, withCard])
            #expect(try reopened.installments().count == 2)
            #expect(throws: RepositoryError.cardInUse) { try reopened.deleteCard(id: Self.card) }
        }
    }
}
