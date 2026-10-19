import Foundation
import Testing
import VademCore

// Depo sözleşmesi: her senaryo yalnızca `any PaymentRepository` üzerinden çalışır.
// Bir sonraki issue'daki SwiftData uygulaması, `RepositoryFactory.all` listesine
// eklenerek aynı senaryolardan geçirilir.
struct RepositoryFactory: Sendable, CustomTestStringConvertible {
    let name: String
    let make: @MainActor @Sendable () throws -> any PaymentRepository

    var testDescription: String { name }

    static let all: [RepositoryFactory] = [
        RepositoryFactory(name: "InMemory") { InMemoryPaymentRepository() },
    ]
}

@MainActor
enum PaymentRepositoryContract {
    // MARK: Kartlar

    static func startsEmpty(_ repo: any PaymentRepository) throws {
        #expect(try repo.cards().isEmpty)
        #expect(try repo.installments().isEmpty)
        #expect(try repo.subscriptions().isEmpty)
    }

    static func cardsSortedByNameCaseInsensitive(_ repo: any PaymentRepository) throws {
        // Ters sırada eklenir; büyük/küçük harf duyarlı sıralama "Bonus"u "axess"ten önce koyardı.
        let world = try Fixture.card("world", id: Fixture.id(1))
        let bonus = try Fixture.card("Bonus", id: Fixture.id(2))
        let axess = try Fixture.card("axess", id: Fixture.id(3))
        try repo.save(world)
        try repo.save(bonus)
        try repo.save(axess)
        #expect(try repo.cards() == [axess, bonus, world])
    }

    static func cardsWithSameNameSortedByID(_ repo: any PaymentRepository) throws {
        // Harf duyarsız olarak aynı adlar: eşitlik id ile bozulur (…1 < …2 < …3).
        let third = try Fixture.card("Bonus", id: Fixture.id(3))
        let first = try Fixture.card("bonus", id: Fixture.id(1))
        let second = try Fixture.card("BONUS", id: Fixture.id(2))
        try repo.save(third)
        try repo.save(first)
        try repo.save(second)
        #expect(try repo.cards() == [first, second, third])
    }

    static func savingCardWithSameIDReplacesIt(_ repo: any PaymentRepository) throws {
        let original = try Fixture.card("Bonus", id: Fixture.id(1))
        let renamed = try #require(Card(id: Fixture.id(1), name: "Maximum", statementDay: 3, dueDay: 13))
        try repo.save(original)
        try repo.save(renamed)
        #expect(try repo.cards() == [renamed])
    }

    static func savingSameCardTwiceDoesNotDuplicate(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        try repo.save(card)
        try repo.save(card)
        #expect(try repo.cards() == [card])
    }

    static func deletesUnusedCard(_ repo: any PaymentRepository) throws {
        let keep = try Fixture.card("Axess", id: Fixture.id(1))
        let remove = try Fixture.card("Bonus", id: Fixture.id(2))
        try repo.save(keep)
        try repo.save(remove)
        try repo.deleteCard(id: remove.id)
        #expect(try repo.cards() == [keep])
    }

    static func deletingUnknownCardIsNoOp(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        try repo.save(card)
        try repo.deleteCard(id: Fixture.id(99))
        #expect(try repo.cards() == [card])
    }

    static func deletingCardInUseByInstallmentThrows(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        let item = try Fixture.installment(card: card.id)
        try repo.save(card)
        try repo.save(item)
        #expect(throws: RepositoryError.cardInUse) { try repo.deleteCard(id: card.id) }
        #expect(try repo.cards() == [card])
        #expect(try repo.installments() == [item])
    }

    static func deletingCardInUseBySubscriptionThrows(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        let item = try Fixture.subscriptionItem(card: card.id)
        try repo.save(card)
        try repo.save(item)
        #expect(throws: RepositoryError.cardInUse) { try repo.deleteCard(id: card.id) }
        #expect(try repo.cards() == [card])
        #expect(try repo.subscriptions() == [item])
    }

    static func cardCanBeDeletedOnceNoLongerReferenced(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        let installment = try Fixture.installment(card: card.id)
        let subscription = try Fixture.subscriptionItem(card: card.id)
        try repo.save(card)
        try repo.save(installment)
        try repo.save(subscription)
        try repo.deleteInstallment(id: installment.id)
        #expect(throws: RepositoryError.cardInUse) { try repo.deleteCard(id: card.id) }
        try repo.deleteSubscription(id: subscription.id)
        try repo.deleteCard(id: card.id)
        #expect(try repo.cards().isEmpty)
    }

    static func movedItemsReleaseTheirOldCard(_ repo: any PaymentRepository) throws {
        // Aynı id ile yeniden kaydedilen kalem eski kartı artık kullanmaz.
        let old = try Fixture.card("Eski", id: Fixture.id(1))
        let new = try Fixture.card("Yeni", id: Fixture.id(2))
        try repo.save(old)
        try repo.save(new)
        let installment = try Fixture.installment(id: Fixture.id(10), card: old.id)
        let subscription = try Fixture.subscriptionItem(id: Fixture.id(11), card: old.id)
        try repo.save(installment)
        try repo.save(subscription)
        try repo.save(Fixture.installment(id: Fixture.id(10), card: new.id))
        try repo.save(Fixture.subscriptionItem(id: Fixture.id(11), card: nil))
        try repo.deleteCard(id: old.id)
        #expect(try repo.cards() == [new])
        #expect(throws: RepositoryError.cardInUse) { try repo.deleteCard(id: new.id) }
    }

    static func subscriptionWithoutCardDoesNotBlockDeletion(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        try repo.save(card)
        try repo.save(Fixture.subscriptionItem(card: nil))
        try repo.deleteCard(id: card.id)
        #expect(try repo.cards().isEmpty)
        #expect(try repo.subscriptions().count == 1)
    }

    // MARK: Taksitler

    static func installmentsSortedByFirstMonthThenTitle(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        try repo.save(card)
        // Başlık sırası ile ay sırası çelişecek şekilde seçildi.
        let march = try Fixture.installment("Ayakkabı", card: card.id, plan: Fixture.plan(first: Fixture.month(2026, 3)))
        let lastYear = try Fixture.installment("Zımba", card: card.id, plan: Fixture.plan(first: Fixture.month(2025, 12)))
        let januaryB = try Fixture.installment("Telefon", card: card.id, plan: Fixture.plan(first: Fixture.month(2026, 1)))
        let januaryA = try Fixture.installment("Koltuk", card: card.id, plan: Fixture.plan(first: Fixture.month(2026, 1)))
        for item in [march, januaryB, lastYear, januaryA] {
            try repo.save(item)
        }
        #expect(try repo.installments() == [lastYear, januaryA, januaryB, march])
    }

    static func savingInstallmentWithSameIDReplacesIt(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        try repo.save(card)
        let original = try Fixture.installment("Telefon", id: Fixture.id(1), card: card.id)
        let updated = try Fixture.installment(
            "Telefon (yeni)", id: Fixture.id(1), card: card.id,
            plan: Fixture.plan(total: Decimal(string: "2500.50")!, count: 12, first: Fixture.month(2026, 6))
        )
        try repo.save(original)
        try repo.save(updated)
        #expect(try repo.installments() == [updated])
    }

    static func installmentWithUnknownCardThrows(_ repo: any PaymentRepository) throws {
        try repo.save(Fixture.card(id: Fixture.id(1)))
        let item = try Fixture.installment(card: Fixture.id(2))
        #expect(throws: RepositoryError.unknownCard) { try repo.save(item) }
        #expect(try repo.installments().isEmpty)
    }

    static func installmentForDeletedCardThrows(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        try repo.save(card)
        try repo.deleteCard(id: card.id)
        #expect(throws: RepositoryError.unknownCard) { try repo.save(Fixture.installment(card: card.id)) }
        #expect(try repo.installments().isEmpty)
    }

    static func deletesInstallment(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        try repo.save(card)
        let keep = try Fixture.installment("Koltuk", card: card.id)
        let remove = try Fixture.installment("Telefon", card: card.id)
        try repo.save(keep)
        try repo.save(remove)
        try repo.deleteInstallment(id: remove.id)
        #expect(try repo.installments() == [keep])
    }

    static func deletingUnknownInstallmentIsNoOp(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        try repo.save(card)
        let item = try Fixture.installment(card: card.id)
        try repo.save(item)
        try repo.deleteInstallment(id: Fixture.id(99))
        #expect(try repo.installments() == [item])
    }

    // MARK: Abonelikler

    static func subscriptionsSortedByTitle(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        try repo.save(card)
        let video = try Fixture.subscriptionItem("Video", id: Fixture.id(1), card: card.id)
        let bulut = try Fixture.subscriptionItem("Bulut", id: Fixture.id(2), card: nil)
        let muzik = try Fixture.subscriptionItem("Müzik", id: Fixture.id(3), card: card.id)
        for item in [video, muzik, bulut] {
            try repo.save(item)
        }
        #expect(try repo.subscriptions() == [bulut, muzik, video])
    }

    static func savingSubscriptionWithSameIDReplacesIt(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        try repo.save(card)
        let original = try Fixture.subscriptionItem("Müzik", id: Fixture.id(1), card: card.id)
        let updated = try Fixture.subscriptionItem(
            "Müzik Aile", id: Fixture.id(1), card: nil,
            subscription: Fixture.subscription(amount: 1499, period: .yearly)
        )
        try repo.save(original)
        try repo.save(updated)
        #expect(try repo.subscriptions() == [updated])
    }

    static func subscriptionWithUnknownCardThrows(_ repo: any PaymentRepository) throws {
        try repo.save(Fixture.card(id: Fixture.id(1)))
        let item = try Fixture.subscriptionItem(card: Fixture.id(2))
        #expect(throws: RepositoryError.unknownCard) { try repo.save(item) }
        #expect(try repo.subscriptions().isEmpty)
    }

    static func subscriptionWithoutCardNeedsNoCard(_ repo: any PaymentRepository) throws {
        // Hiç kart yokken bile kartsız abonelik kaydedilebilir.
        let item = try Fixture.subscriptionItem(card: nil)
        try repo.save(item)
        #expect(try repo.subscriptions() == [item])
    }

    static func deletesSubscription(_ repo: any PaymentRepository) throws {
        let keep = try Fixture.subscriptionItem("Bulut", card: nil)
        let remove = try Fixture.subscriptionItem("Video", card: nil)
        try repo.save(keep)
        try repo.save(remove)
        try repo.deleteSubscription(id: remove.id)
        #expect(try repo.subscriptions() == [keep])
    }

    static func deletingUnknownSubscriptionIsNoOp(_ repo: any PaymentRepository) throws {
        let item = try Fixture.subscriptionItem(card: nil)
        try repo.save(item)
        try repo.deleteSubscription(id: Fixture.id(99))
        #expect(try repo.subscriptions() == [item])
    }

    static func valuesComeBackExactlyAsSaved(_ repo: any PaymentRepository) throws {
        let card = try #require(Card(id: Fixture.id(1), name: "Bonus Platinum", statementDay: 31, dueDay: 10))
        let installment = try Fixture.installment(
            "Bilgisayar", id: Fixture.id(2), card: card.id,
            plan: Fixture.plan(total: Decimal(string: "12345.67")!, count: 36, first: Fixture.month(2026, 2))
        )
        let subscription = try Fixture.subscriptionItem(
            "Bulut", id: Fixture.id(3), card: card.id,
            subscription: Fixture.subscription(amount: Decimal(string: "0.99")!, period: .yearly)
        )
        try repo.save(card)
        try repo.save(installment)
        try repo.save(subscription)
        let storedCard = try #require(try repo.cards().first)
        let storedInstallment = try #require(try repo.installments().first)
        let storedSubscription = try #require(try repo.subscriptions().first)
        #expect(storedCard == card)
        #expect(storedInstallment == installment)
        #expect(storedInstallment.plan.total == Money(Decimal(string: "12345.67")!))
        #expect(storedSubscription == subscription)
    }
}

// Senaryoları her depo uygulaması için çalıştırır.
@MainActor
@Suite("PaymentRepository contract")
struct PaymentRepositoryContractTests {
    private typealias Contract = PaymentRepositoryContract

    @Test("A new repository is empty", arguments: RepositoryFactory.all)
    func startsEmpty(factory: RepositoryFactory) throws {
        try Contract.startsEmpty(factory.make())
    }

    @Test("Cards are sorted by name, case-insensitively", arguments: RepositoryFactory.all)
    func cardsSortedByName(factory: RepositoryFactory) throws {
        try Contract.cardsSortedByNameCaseInsensitive(factory.make())
    }

    @Test("Cards with the same name are sorted by id", arguments: RepositoryFactory.all)
    func cardsTieByID(factory: RepositoryFactory) throws {
        try Contract.cardsWithSameNameSortedByID(factory.make())
    }

    @Test("Saving a card with an existing id replaces it", arguments: RepositoryFactory.all)
    func cardUpsert(factory: RepositoryFactory) throws {
        try Contract.savingCardWithSameIDReplacesIt(factory.make())
    }

    @Test("Saving the same card twice does not duplicate it", arguments: RepositoryFactory.all)
    func cardNoDuplicate(factory: RepositoryFactory) throws {
        try Contract.savingSameCardTwiceDoesNotDuplicate(factory.make())
    }

    @Test("An unused card can be deleted", arguments: RepositoryFactory.all)
    func deleteCard(factory: RepositoryFactory) throws {
        try Contract.deletesUnusedCard(factory.make())
    }

    @Test("Deleting an unknown card id is a no-op", arguments: RepositoryFactory.all)
    func deleteUnknownCard(factory: RepositoryFactory) throws {
        try Contract.deletingUnknownCardIsNoOp(factory.make())
    }

    @Test("A card used by an installment cannot be deleted", arguments: RepositoryFactory.all)
    func cardInUseByInstallment(factory: RepositoryFactory) throws {
        try Contract.deletingCardInUseByInstallmentThrows(factory.make())
    }

    @Test("A card used by a subscription cannot be deleted", arguments: RepositoryFactory.all)
    func cardInUseBySubscription(factory: RepositoryFactory) throws {
        try Contract.deletingCardInUseBySubscriptionThrows(factory.make())
    }

    @Test("A card can be deleted once nothing references it", arguments: RepositoryFactory.all)
    func cardFreedAfterItemsDeleted(factory: RepositoryFactory) throws {
        try Contract.cardCanBeDeletedOnceNoLongerReferenced(factory.make())
    }

    @Test("Items moved to another card release the old one", arguments: RepositoryFactory.all)
    func movedItemsReleaseCard(factory: RepositoryFactory) throws {
        try Contract.movedItemsReleaseTheirOldCard(factory.make())
    }

    @Test("A subscription without a card does not block card deletion", arguments: RepositoryFactory.all)
    func cardlessSubscriptionDoesNotBlock(factory: RepositoryFactory) throws {
        try Contract.subscriptionWithoutCardDoesNotBlockDeletion(factory.make())
    }

    @Test("Installments are sorted by first month, then title", arguments: RepositoryFactory.all)
    func installmentsSorted(factory: RepositoryFactory) throws {
        try Contract.installmentsSortedByFirstMonthThenTitle(factory.make())
    }

    @Test("Saving an installment with an existing id replaces it", arguments: RepositoryFactory.all)
    func installmentUpsert(factory: RepositoryFactory) throws {
        try Contract.savingInstallmentWithSameIDReplacesIt(factory.make())
    }

    @Test("An installment for an unknown card is rejected", arguments: RepositoryFactory.all)
    func installmentUnknownCard(factory: RepositoryFactory) throws {
        try Contract.installmentWithUnknownCardThrows(factory.make())
    }

    @Test("An installment for a deleted card is rejected", arguments: RepositoryFactory.all)
    func installmentDeletedCard(factory: RepositoryFactory) throws {
        try Contract.installmentForDeletedCardThrows(factory.make())
    }

    @Test("An installment can be deleted", arguments: RepositoryFactory.all)
    func deleteInstallment(factory: RepositoryFactory) throws {
        try Contract.deletesInstallment(factory.make())
    }

    @Test("Deleting an unknown installment id is a no-op", arguments: RepositoryFactory.all)
    func deleteUnknownInstallment(factory: RepositoryFactory) throws {
        try Contract.deletingUnknownInstallmentIsNoOp(factory.make())
    }

    @Test("Subscriptions are sorted by title", arguments: RepositoryFactory.all)
    func subscriptionsSorted(factory: RepositoryFactory) throws {
        try Contract.subscriptionsSortedByTitle(factory.make())
    }

    @Test("Saving a subscription with an existing id replaces it", arguments: RepositoryFactory.all)
    func subscriptionUpsert(factory: RepositoryFactory) throws {
        try Contract.savingSubscriptionWithSameIDReplacesIt(factory.make())
    }

    @Test("A subscription for an unknown card is rejected", arguments: RepositoryFactory.all)
    func subscriptionUnknownCard(factory: RepositoryFactory) throws {
        try Contract.subscriptionWithUnknownCardThrows(factory.make())
    }

    @Test("A subscription without a card is saved without any cards", arguments: RepositoryFactory.all)
    func cardlessSubscription(factory: RepositoryFactory) throws {
        try Contract.subscriptionWithoutCardNeedsNoCard(factory.make())
    }

    @Test("A subscription can be deleted", arguments: RepositoryFactory.all)
    func deleteSubscription(factory: RepositoryFactory) throws {
        try Contract.deletesSubscription(factory.make())
    }

    @Test("Deleting an unknown subscription id is a no-op", arguments: RepositoryFactory.all)
    func deleteUnknownSubscription(factory: RepositoryFactory) throws {
        try Contract.deletingUnknownSubscriptionIsNoOp(factory.make())
    }

    @Test("Values come back exactly as saved", arguments: RepositoryFactory.all)
    func exactValues(factory: RepositoryFactory) throws {
        try Contract.valuesComeBackExactlyAsSaved(factory.make())
    }
}
