import Foundation
import SwiftData

/// The third store schema: adds one-time payments.
///
/// Changes from ``VademSchemaV2``: a new `OneTimePaymentRecord` entity. Cards, installments
/// and subscriptions are unchanged.
/// Never change this schema in place once shipped; a change adds `VademSchemaV4` and a migration stage.
public enum VademSchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [CardRecord.self, InstallmentRecord.self, SubscriptionRecord.self, OneTimePaymentRecord.self]
    }

    // V2'nin modelleri olduğu gibi kalır; V3 kendi kopyalarını tanımlar (varlık adları aynı).

    @Model
    final class CardRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var statementDay: Int
        var dueDay: Int

        init(id: UUID, name: String, statementDay: Int, dueDay: Int) {
            self.id = id
            self.name = name
            self.statementDay = statementDay
            self.dueDay = dueDay
        }
    }

    @Model
    final class InstallmentRecord {
        @Attribute(.unique) var id: UUID
        var title: String
        // Kartsız taksitte nil; V1'den gelen kayıtlarda her zaman dolu.
        var cardID: UUID?
        // Yalnızca kartsız taksitte dolu; V1'den gelen kayıtlarda nil.
        var paymentDay: Int?
        var total: String
        var count: Int
        var firstYear: Int
        var firstMonth: Int

        init(
            id: UUID, title: String, cardID: UUID?, paymentDay: Int?, total: String, count: Int,
            firstYear: Int, firstMonth: Int
        ) {
            self.id = id
            self.title = title
            self.cardID = cardID
            self.paymentDay = paymentDay
            self.total = total
            self.count = count
            self.firstYear = firstYear
            self.firstMonth = firstMonth
        }
    }

    @Model
    final class SubscriptionRecord {
        @Attribute(.unique) var id: UUID
        var title: String
        var cardID: UUID?
        var amount: String
        var period: String
        var renewalDay: Int
        var firstYear: Int
        var firstMonth: Int
        // İkisi birlikte ya dolu ya boş; biri tek başına doluysa kayıt geçersiz sayılır.
        var lastYear: Int?
        var lastMonth: Int?

        init(
            id: UUID, title: String, cardID: UUID?, amount: String, period: String, renewalDay: Int,
            firstYear: Int, firstMonth: Int, lastYear: Int?, lastMonth: Int?
        ) {
            self.id = id
            self.title = title
            self.cardID = cardID
            self.amount = amount
            self.period = period
            self.renewalDay = renewalDay
            self.firstYear = firstYear
            self.firstMonth = firstMonth
            self.lastYear = lastYear
            self.lastMonth = lastMonth
        }
    }

    @Model
    final class OneTimePaymentRecord {
        @Attribute(.unique) var id: UUID
        var title: String
        var cardID: UUID?
        var amount: String
        // Vade günü yıl, ay ve gün olarak saklanır (Date değil): saat dilimi değişince gün kaymaz.
        var dueYear: Int
        var dueMonth: Int
        var dueDay: Int

        init(id: UUID, title: String, cardID: UUID?, amount: String, dueYear: Int, dueMonth: Int, dueDay: Int) {
            self.id = id
            self.title = title
            self.cardID = cardID
            self.amount = amount
            self.dueYear = dueYear
            self.dueMonth = dueMonth
            self.dueDay = dueDay
        }
    }
}
