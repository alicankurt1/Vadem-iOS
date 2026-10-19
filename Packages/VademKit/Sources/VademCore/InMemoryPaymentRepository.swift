import Foundation

/// A ``PaymentRepository`` that keeps everything in memory.
///
/// The reference implementation of the repository rules, used for previews and tests.
/// Nothing is persisted; a new instance starts empty.
@MainActor
public final class InMemoryPaymentRepository: PaymentRepository {
    // id'ye göre sözlük: aynı id ile kaydetmek eskisinin yerine geçer, kopya oluşmaz.
    private var cardsByID: [Card.ID: Card] = [:]
    private var installmentsByID: [InstallmentItem.ID: InstallmentItem] = [:]
    private var subscriptionsByID: [SubscriptionItem.ID: SubscriptionItem] = [:]

    /// Creates an empty repository.
    public init() {}

    public func cards() throws -> [Card] {
        cardsByID.values.sorted { lhs, rhs in
            Self.isOrdered(lhs.name, lhs.id, before: rhs.name, rhs.id)
        }
    }

    public func save(_ card: Card) throws {
        cardsByID[card.id] = card
    }

    public func deleteCard(id: Card.ID) throws {
        guard cardsByID[id] != nil else { return }
        // Kullanımdaki kart silinemez; aksi halde taksit/abonelik sahipsiz kalırdı.
        let isUsed = installmentsByID.values.contains { $0.cardID == id }
            || subscriptionsByID.values.contains { $0.cardID == id }
        if isUsed { throw RepositoryError.cardInUse }
        cardsByID[id] = nil
    }

    public func installments() throws -> [InstallmentItem] {
        installmentsByID.values.sorted { lhs, rhs in
            if lhs.plan.firstMonth != rhs.plan.firstMonth {
                return lhs.plan.firstMonth < rhs.plan.firstMonth
            }
            return Self.isOrdered(lhs.title, lhs.id, before: rhs.title, rhs.id)
        }
    }

    public func save(_ item: InstallmentItem) throws {
        guard cardsByID[item.cardID] != nil else { throw RepositoryError.unknownCard }
        installmentsByID[item.id] = item
    }

    public func deleteInstallment(id: InstallmentItem.ID) throws {
        installmentsByID[id] = nil
    }

    public func subscriptions() throws -> [SubscriptionItem] {
        subscriptionsByID.values.sorted { lhs, rhs in
            Self.isOrdered(lhs.title, lhs.id, before: rhs.title, rhs.id)
        }
    }

    public func save(_ item: SubscriptionItem) throws {
        // Kartsız abonelik (nil) serbest; kart verilmişse kayıtlı olmalı.
        if let cardID = item.cardID, cardsByID[cardID] == nil {
            throw RepositoryError.unknownCard
        }
        subscriptionsByID[item.id] = item
    }

    public func deleteSubscription(id: SubscriptionItem.ID) throws {
        subscriptionsByID[id] = nil
    }

    // Sözlük sırası belirsiz olduğu için eşitlikte id ile ayırıyoruz; sonuç her zaman aynı.
    // Karşılaştırma büyük/küçük harfe duyarsız ve yerel ayardan bağımsız.
    private static func isOrdered(_ lhsText: String, _ lhsID: UUID, before rhsText: String, _ rhsID: UUID) -> Bool {
        switch lhsText.caseInsensitiveCompare(rhsText) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhsID.uuidString < rhsID.uuidString
        }
    }
}
