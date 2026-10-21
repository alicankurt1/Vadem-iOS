import Foundation
import Testing
import VademCore

// Depo sözleşmesi: her senaryo yalnızca `any PaymentRepository` üzerinden çalışır.
// Her `PaymentRepository` uygulaması (bellek içi, SwiftData, …) kendi test hedefinde
// aynı `scenarios` listesinden geçirilir; davranışları böylece birebir aynı kalır.
@MainActor
public enum PaymentRepositoryContract {
    // MARK: Kartlar

    public static func startsEmpty(_ repo: any PaymentRepository) throws {
        #expect(try repo.cards().isEmpty)
        #expect(try repo.installments().isEmpty)
        #expect(try repo.subscriptions().isEmpty)
    }

    public static func cardsSortedByNameCaseInsensitive(_ repo: any PaymentRepository) throws {
        // Ters sırada eklenir; büyük/küçük harf duyarlı sıralama "Bonus"u "axess"ten önce koyardı.
        let world = try Fixture.card("world", id: Fixture.id(1))
        let bonus = try Fixture.card("Bonus", id: Fixture.id(2))
        let axess = try Fixture.card("axess", id: Fixture.id(3))
        try repo.save(world)
        try repo.save(bonus)
        try repo.save(axess)
        #expect(try repo.cards() == [axess, bonus, world])
    }

    public static func cardsWithSameNameSortedByID(_ repo: any PaymentRepository) throws {
        // Harf duyarsız olarak aynı adlar: eşitlik id ile bozulur (…1 < …2 < …3).
        let third = try Fixture.card("Bonus", id: Fixture.id(3))
        let first = try Fixture.card("bonus", id: Fixture.id(1))
        let second = try Fixture.card("BONUS", id: Fixture.id(2))
        try repo.save(third)
        try repo.save(first)
        try repo.save(second)
        #expect(try repo.cards() == [first, second, third])
    }

    public static func savingCardWithSameIDReplacesIt(_ repo: any PaymentRepository) throws {
        let original = try Fixture.card("Bonus", id: Fixture.id(1))
        let renamed = try #require(Card(id: Fixture.id(1), name: "Maximum", statementDay: 3, dueDay: 13))
        try repo.save(original)
        try repo.save(renamed)
        #expect(try repo.cards() == [renamed])
    }

    public static func savingSameCardTwiceDoesNotDuplicate(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        try repo.save(card)
        try repo.save(card)
        #expect(try repo.cards() == [card])
    }

    public static func deletesUnusedCard(_ repo: any PaymentRepository) throws {
        let keep = try Fixture.card("Axess", id: Fixture.id(1))
        let remove = try Fixture.card("Bonus", id: Fixture.id(2))
        try repo.save(keep)
        try repo.save(remove)
        try repo.deleteCard(id: remove.id)
        #expect(try repo.cards() == [keep])
    }

    public static func deletingUnknownCardIsNoOp(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        try repo.save(card)
        try repo.deleteCard(id: Fixture.id(99))
        #expect(try repo.cards() == [card])
    }

    public static func deletingCardInUseByInstallmentThrows(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        let item = try Fixture.installment(card: card.id)
        try repo.save(card)
        try repo.save(item)
        #expect(throws: RepositoryError.cardInUse) { try repo.deleteCard(id: card.id) }
        #expect(try repo.cards() == [card])
        #expect(try repo.installments() == [item])
    }

    public static func deletingCardInUseBySubscriptionThrows(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        let item = try Fixture.subscriptionItem(card: card.id)
        try repo.save(card)
        try repo.save(item)
        #expect(throws: RepositoryError.cardInUse) { try repo.deleteCard(id: card.id) }
        #expect(try repo.cards() == [card])
        #expect(try repo.subscriptions() == [item])
    }

    public static func cardCanBeDeletedOnceNoLongerReferenced(_ repo: any PaymentRepository) throws {
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

    public static func movedItemsReleaseTheirOldCard(_ repo: any PaymentRepository) throws {
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

    public static func subscriptionWithoutCardDoesNotBlockDeletion(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        try repo.save(card)
        try repo.save(Fixture.subscriptionItem(card: nil))
        try repo.deleteCard(id: card.id)
        #expect(try repo.cards().isEmpty)
        #expect(try repo.subscriptions().count == 1)
    }

    // MARK: Taksitler

    public static func installmentsSortedByFirstMonthThenTitle(_ repo: any PaymentRepository) throws {
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

    public static func installmentsWithSameMonthAndTitleSortedByID(_ repo: any PaymentRepository) throws {
        // Aynı ay, harf duyarsız olarak aynı başlık: eşitlik id ile bozulur (…1 < …2 < …3).
        let card = try Fixture.card()
        try repo.save(card)
        let plan = try Fixture.plan(first: Fixture.month(2026, 4))
        let second = try Fixture.installment("koltuk", id: Fixture.id(2), card: card.id, plan: plan)
        let third = try Fixture.installment("KOLTUK", id: Fixture.id(3), card: card.id, plan: plan)
        let first = try Fixture.installment("Koltuk", id: Fixture.id(1), card: card.id, plan: plan)
        for item in [second, third, first] {
            try repo.save(item)
        }
        #expect(try repo.installments() == [first, second, third])
    }

    public static func installmentTitlesComparedCaseInsensitively(_ repo: any PaymentRepository) throws {
        // Aynı ayda; harf duyarlı sıralama "Zımba"yı "ayna"dan önce koyardı.
        let card = try Fixture.card()
        try repo.save(card)
        let plan = try Fixture.plan(first: Fixture.month(2026, 4))
        let zimba = try Fixture.installment("Zımba", card: card.id, plan: plan)
        let ayna = try Fixture.installment("ayna", card: card.id, plan: plan)
        try repo.save(zimba)
        try repo.save(ayna)
        #expect(try repo.installments() == [ayna, zimba])
    }

    public static func savingInstallmentWithSameIDReplacesIt(_ repo: any PaymentRepository) throws {
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

    public static func installmentWithUnknownCardThrows(_ repo: any PaymentRepository) throws {
        try repo.save(Fixture.card(id: Fixture.id(1)))
        let item = try Fixture.installment(card: Fixture.id(2))
        #expect(throws: RepositoryError.unknownCard) { try repo.save(item) }
        #expect(try repo.installments().isEmpty)
    }

    public static func installmentForDeletedCardThrows(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        try repo.save(card)
        try repo.deleteCard(id: card.id)
        #expect(throws: RepositoryError.unknownCard) { try repo.save(Fixture.installment(card: card.id)) }
        #expect(try repo.installments().isEmpty)
    }

    public static func deletesInstallment(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        try repo.save(card)
        let keep = try Fixture.installment("Koltuk", card: card.id)
        let remove = try Fixture.installment("Telefon", card: card.id)
        try repo.save(keep)
        try repo.save(remove)
        try repo.deleteInstallment(id: remove.id)
        #expect(try repo.installments() == [keep])
    }

    public static func deletingUnknownInstallmentIsNoOp(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        try repo.save(card)
        let item = try Fixture.installment(card: card.id)
        try repo.save(item)
        try repo.deleteInstallment(id: Fixture.id(99))
        #expect(try repo.installments() == [item])
    }

    public static func draftItemIsStoredAndReadBack(_ repo: any PaymentRepository) throws {
        // Formdan gelen (kırpılmış başlık, kuruşa yuvarlanmış tutar) kalem aynen geri okunur.
        let card = try Fixture.card()
        try repo.save(card)
        let draft = InstallmentDraft(
            title: "  Telefon  ", cardID: card.id, total: Decimal(string: "1499.90")!,
            count: 6, firstMonth: try Fixture.month(2026, 11)
        )
        let item = try #require(draft.makeItem(id: Fixture.id(1)))
        try repo.save(item)
        let stored = try #require(try repo.installments().first)
        #expect(try repo.installments().count == 1)
        #expect(stored == item)
        #expect(stored.title == "Telefon")
        #expect(stored.plan.total == Money(Decimal(string: "1499.90")!))
        #expect(stored.plan.firstMonth == (try Fixture.month(2026, 11)))
    }

    public static func newInstallmentAppearsInItsMonths(_ repo: any PaymentRepository) throws {
        let card = try Fixture.card()
        try repo.save(card)
        let before = try repo.installments()
        let item = try Fixture.installment(
            "Koltuk", card: card.id, plan: Fixture.plan(total: 900, count: 3, first: Fixture.month(2026, 12))
        )
        try repo.save(item)
        let after = try repo.installments()
        #expect(before.isEmpty)
        #expect(after.map(\.id) == [item.id])
        #expect(after.first?.plan.amount(in: try Fixture.month(2026, 12)) == Money(300))
        #expect(after.first?.plan.amount(in: try Fixture.month(2027, 2)) == Money(300))
        #expect(after.first?.plan.amount(in: try Fixture.month(2027, 3)) == .zero)
    }

    // MARK: Abonelikler

    public static func subscriptionsSortedByTitle(_ repo: any PaymentRepository) throws {
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

    public static func subscriptionsWithSameTitleSortedByID(_ repo: any PaymentRepository) throws {
        // Harf duyarsız olarak aynı başlık: eşitlik id ile bozulur (…1 < …2 < …3).
        let second = try Fixture.subscriptionItem("müzik", id: Fixture.id(2), card: nil)
        let third = try Fixture.subscriptionItem("MÜZIK", id: Fixture.id(3), card: nil)
        let first = try Fixture.subscriptionItem("Müzik", id: Fixture.id(1), card: nil)
        for item in [third, second, first] {
            try repo.save(item)
        }
        #expect(try repo.subscriptions() == [first, second, third])
    }

    public static func subscriptionTitlesUseNonLocalizedCaseInsensitiveCompare(_ repo: any PaymentRepository) throws {
        // Beklenen sıra yalnızca `String.caseInsensitiveCompare` (yerelleştirilmemiş) kuralından
        // ayrı bir betikle hesaplandı: ayna, Çiçek, Işık, Ozan, Zımba, ılık.
        // Türkçe yerel sıralama "ılık"ı "Işık"ın yanına koyardı; harf duyarlı sıralama "ayna"yı sona atardı.
        let titles = ["Zımba", "ılık", "Çiçek", "Işık", "ayna", "Ozan"]
        var saved: [String: SubscriptionItem] = [:]
        for (offset, title) in titles.enumerated() {
            let item = try Fixture.subscriptionItem(title, id: Fixture.id(offset + 1), card: nil)
            saved[title] = item
            try repo.save(item)
        }
        let expected = try ["ayna", "Çiçek", "Işık", "Ozan", "Zımba", "ılık"].map { try #require(saved[$0]) }
        #expect(try repo.subscriptions().map(\.title) == expected.map(\.title))
        #expect(try repo.subscriptions() == expected)
    }

    public static func savingSubscriptionWithSameIDReplacesIt(_ repo: any PaymentRepository) throws {
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

    public static func subscriptionWithUnknownCardThrows(_ repo: any PaymentRepository) throws {
        try repo.save(Fixture.card(id: Fixture.id(1)))
        let item = try Fixture.subscriptionItem(card: Fixture.id(2))
        #expect(throws: RepositoryError.unknownCard) { try repo.save(item) }
        #expect(try repo.subscriptions().isEmpty)
    }

    public static func subscriptionWithoutCardNeedsNoCard(_ repo: any PaymentRepository) throws {
        // Hiç kart yokken bile kartsız abonelik kaydedilebilir.
        let item = try Fixture.subscriptionItem(card: nil)
        try repo.save(item)
        #expect(try repo.subscriptions() == [item])
    }

    public static func deletesSubscription(_ repo: any PaymentRepository) throws {
        let keep = try Fixture.subscriptionItem("Bulut", card: nil)
        let remove = try Fixture.subscriptionItem("Video", card: nil)
        try repo.save(keep)
        try repo.save(remove)
        try repo.deleteSubscription(id: remove.id)
        #expect(try repo.subscriptions() == [keep])
    }

    public static func deletingUnknownSubscriptionIsNoOp(_ repo: any PaymentRepository) throws {
        let item = try Fixture.subscriptionItem(card: nil)
        try repo.save(item)
        try repo.deleteSubscription(id: Fixture.id(99))
        #expect(try repo.subscriptions() == [item])
    }

    public static func valuesComeBackExactlyAsSaved(_ repo: any PaymentRepository) throws {
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

    /// Her senaryo bir test olarak koşar; adı test raporunda görünür.
    public struct Scenario: Sendable, CustomTestStringConvertible {
        public let name: String
        public let run: @MainActor @Sendable (any PaymentRepository) throws -> Void
        public var testDescription: String { name }
    }

    /// Sözleşmenin tamamı. Yeni bir uygulama bu listeyi `@Test(arguments: factories, scenarios)` ile koşar.
    nonisolated public static let scenarios: [Scenario] = [
        Scenario(name: "A new repository is empty", run: startsEmpty),
        Scenario(name: "Cards are sorted by name, case-insensitively", run: cardsSortedByNameCaseInsensitive),
        Scenario(name: "Cards with the same name are sorted by id", run: cardsWithSameNameSortedByID),
        Scenario(name: "Saving a card with an existing id replaces it", run: savingCardWithSameIDReplacesIt),
        Scenario(name: "Saving the same card twice does not duplicate it", run: savingSameCardTwiceDoesNotDuplicate),
        Scenario(name: "An unused card can be deleted", run: deletesUnusedCard),
        Scenario(name: "Deleting an unknown card id is a no-op", run: deletingUnknownCardIsNoOp),
        Scenario(name: "A card used by an installment cannot be deleted", run: deletingCardInUseByInstallmentThrows),
        Scenario(name: "A card used by a subscription cannot be deleted", run: deletingCardInUseBySubscriptionThrows),
        Scenario(name: "A card can be deleted once nothing references it", run: cardCanBeDeletedOnceNoLongerReferenced),
        Scenario(name: "Items moved to another card release the old one", run: movedItemsReleaseTheirOldCard),
        Scenario(name: "A subscription without a card does not block card deletion", run: subscriptionWithoutCardDoesNotBlockDeletion),
        Scenario(name: "Installments are sorted by first month, then title", run: installmentsSortedByFirstMonthThenTitle),
        Scenario(name: "Installments with the same month and title are sorted by id", run: installmentsWithSameMonthAndTitleSortedByID),
        Scenario(name: "Installment titles are compared case-insensitively", run: installmentTitlesComparedCaseInsensitively),
        Scenario(name: "Saving an installment with an existing id replaces it", run: savingInstallmentWithSameIDReplacesIt),
        Scenario(name: "An installment for an unknown card is rejected", run: installmentWithUnknownCardThrows),
        Scenario(name: "An installment for a deleted card is rejected", run: installmentForDeletedCardThrows),
        Scenario(name: "An installment can be deleted", run: deletesInstallment),
        Scenario(name: "Deleting an unknown installment id is a no-op", run: deletingUnknownInstallmentIsNoOp),
        Scenario(name: "Subscriptions are sorted by title", run: subscriptionsSortedByTitle),
        Scenario(name: "Subscriptions with the same title are sorted by id", run: subscriptionsWithSameTitleSortedByID),
        Scenario(name: "Subscription titles use non-localized case-insensitive order", run: subscriptionTitlesUseNonLocalizedCaseInsensitiveCompare),
        Scenario(name: "Saving a subscription with an existing id replaces it", run: savingSubscriptionWithSameIDReplacesIt),
        Scenario(name: "A subscription for an unknown card is rejected", run: subscriptionWithUnknownCardThrows),
        Scenario(name: "A subscription without a card is saved without any cards", run: subscriptionWithoutCardNeedsNoCard),
        Scenario(name: "A subscription can be deleted", run: deletesSubscription),
        Scenario(name: "Deleting an unknown subscription id is a no-op", run: deletingUnknownSubscriptionIsNoOp),
        Scenario(name: "An installment made from a draft is stored and read back", run: draftItemIsStoredAndReadBack),
        Scenario(name: "A new installment is charged in its months only", run: newInstallmentAppearsInItsMonths),
        Scenario(name: "Values come back exactly as saved", run: valuesComeBackExactlyAsSaved),
    ]
}
