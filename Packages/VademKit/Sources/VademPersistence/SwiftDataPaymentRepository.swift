import Foundation
import SwiftData
import VademCore

/// A ``PaymentRepository`` that stores cards, installments and subscriptions with SwiftData.
///
/// Behaves exactly like `InMemoryPaymentRepository`: same order, same errors. Every write
/// is saved to the store immediately; a failed save is rolled back and rethrown.
/// Reading a record that breaks a `VademCore` rule throws ``PersistenceError/invalidRecord(entity:id:)``.
@MainActor
public final class SwiftDataPaymentRepository: PaymentRepository {
    // Context, container'ı canlı tutmaz; container serbest kalırsa context çöker.
    // Bu yüzden container'ı depo ömrü boyunca burada tutuyoruz.
    private let container: ModelContainer
    private let context: ModelContext

    /// Creates a repository on `container`'s main context and keeps the container alive.
    /// Use ``VademPersistence/makeContainer(storage:)`` to create the container.
    public init(container: ModelContainer) {
        self.container = container
        context = container.mainContext
    }

    // MARK: Cards

    public func cards() throws -> [Card] {
        try context.fetch(FetchDescriptor<CardRecord>())
            .map { try $0.value() }
            .sorted { RepositoryOrder.isOrdered($0.name, $0.id, before: $1.name, $1.id) }
    }

    public func save(_ card: Card) throws {
        if let record = try cardRecord(id: card.id) {
            record.update(from: card)
        } else {
            context.insert(CardRecord(card))
        }
        try commit()
    }

    public func deleteCard(id: Card.ID) throws {
        guard let record = try cardRecord(id: id) else { return }
        // Kullanımdaki kart silinemez; ilişki olmadığı için kural burada uygulanır.
        let target: UUID? = id
        let installmentCount = try context.fetchCount(
            FetchDescriptor<InstallmentRecord>(predicate: #Predicate { $0.cardID == target })
        )
        let subscriptionCount = try context.fetchCount(
            FetchDescriptor<SubscriptionRecord>(predicate: #Predicate { $0.cardID == target })
        )
        if installmentCount + subscriptionCount > 0 { throw RepositoryError.cardInUse }
        context.delete(record)
        try commit()
    }

    // MARK: Installments

    public func installments() throws -> [InstallmentItem] {
        try context.fetch(FetchDescriptor<InstallmentRecord>())
            .map { try $0.value() }
            .sorted { lhs, rhs in
                if lhs.plan.firstMonth != rhs.plan.firstMonth {
                    return lhs.plan.firstMonth < rhs.plan.firstMonth
                }
                return RepositoryOrder.isOrdered(lhs.title, lhs.id, before: rhs.title, rhs.id)
            }
    }

    public func save(_ item: InstallmentItem) throws {
        // Kartsız taksit (nil) serbest; kart verilmişse kayıtlı olmalı.
        if let cardID = item.cardID, try !cardExists(id: cardID) {
            throw RepositoryError.unknownCard
        }
        let id = item.id
        if let record = try context.fetch(FetchDescriptor<InstallmentRecord>(predicate: #Predicate { $0.id == id })).first {
            record.update(from: item)
        } else {
            context.insert(InstallmentRecord(item))
        }
        try commit()
    }

    public func deleteInstallment(id: InstallmentItem.ID) throws {
        try context.delete(model: InstallmentRecord.self, where: #Predicate { $0.id == id })
        try commit()
    }

    // MARK: Subscriptions

    public func subscriptions() throws -> [SubscriptionItem] {
        try context.fetch(FetchDescriptor<SubscriptionRecord>())
            .map { try $0.value() }
            .sorted { RepositoryOrder.isOrdered($0.title, $0.id, before: $1.title, $1.id) }
    }

    public func save(_ item: SubscriptionItem) throws {
        // Kartsız abonelik (nil) serbest; kart verilmişse kayıtlı olmalı.
        if let cardID = item.cardID, try !cardExists(id: cardID) {
            throw RepositoryError.unknownCard
        }
        let id = item.id
        if let record = try context.fetch(FetchDescriptor<SubscriptionRecord>(predicate: #Predicate { $0.id == id })).first {
            record.update(from: item)
        } else {
            context.insert(SubscriptionRecord(item))
        }
        try commit()
    }

    public func deleteSubscription(id: SubscriptionItem.ID) throws {
        try context.delete(model: SubscriptionRecord.self, where: #Predicate { $0.id == id })
        try commit()
    }

    // MARK: Helpers

    private func cardRecord(id: UUID) throws -> CardRecord? {
        try context.fetch(FetchDescriptor<CardRecord>(predicate: #Predicate { $0.id == id })).first
    }

    private func cardExists(id: UUID) throws -> Bool {
        try context.fetchCount(FetchDescriptor<CardRecord>(predicate: #Predicate { $0.id == id })) > 0
    }

    // Her yazma hemen kaydedilir. Kayıt başarısızsa bekleyen değişiklikler geri alınır;
    // böylece bağlam, diskteki veriyle tutarlı kalır.
    private func commit() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

// InMemoryPaymentRepository ile aynı metin sırası: harf duyarsız, yerel ayardan bağımsız;
// eşitlikte `id.uuidString`. Kural PaymentRepository belgesinde tanımlı.
enum RepositoryOrder {
    static func isOrdered(_ lhsText: String, _ lhsID: UUID, before rhsText: String, _ rhsID: UUID) -> Bool {
        switch lhsText.caseInsensitiveCompare(rhsText) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhsID.uuidString < rhsID.uuidString
        }
    }
}
