import Foundation
import SwiftData

/// The second store schema: an installment's card is optional and a card-less installment
/// keeps its own payment day.
///
/// Changes from ``VademSchemaV1``: `InstallmentRecord.cardID` becomes `UUID?` and
/// `InstallmentRecord.paymentDay: Int?` is added. Cards and subscriptions are unchanged.
/// Never change this schema in place once shipped; a change adds `VademSchemaV3` and a migration stage.
public enum VademSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [CardRecord.self, InstallmentRecord.self, SubscriptionRecord.self]
    }

    // V1'in modelleri olduğu gibi kalır; V2 kendi kopyalarını tanımlar (varlık adları aynı).

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
}

// Güncel şemanın kayıtları; depo ve eşleme kodu sürüm adını tekrar etmez.
typealias CardRecord = VademSchemaV2.CardRecord
typealias InstallmentRecord = VademSchemaV2.InstallmentRecord
typealias SubscriptionRecord = VademSchemaV2.SubscriptionRecord

/// The migration plan for the store: V1 → V2 is a lightweight stage (an attribute becomes
/// optional and an optional attribute is added), so every saved record is kept as is.
public enum VademMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [VademSchemaV1.self, VademSchemaV2.self] }

    public static var stages: [MigrationStage] { [migrateV1toV2] }

    // V1 → V2: `InstallmentRecord.cardID` isteğe bağlı olur, `paymentDay` eklenir (eski kayıtlarda nil).
    // Hesaplanan özellik: MigrationStage Sendable değil, statik saklı değer olamaz.
    static var migrateV1toV2: MigrationStage {
        .lightweight(fromVersion: VademSchemaV1.self, toVersion: VademSchemaV2.self)
    }
}
