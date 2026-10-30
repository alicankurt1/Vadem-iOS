import Foundation
import SwiftData

/// The fourth store schema: adds the in-app inbox.
///
/// Changes from ``VademSchemaV3``: a new `InboxEntryRecord` entity (inbox entries, their read
/// state and the ids of deleted entries). Cards, installments, subscriptions and one-time
/// payments are unchanged.
/// Never change this schema in place once shipped; a change adds `VademSchemaV5` and a migration stage.
public enum VademSchemaV4: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            CardRecord.self, InstallmentRecord.self, SubscriptionRecord.self, OneTimePaymentRecord.self,
            InboxEntryRecord.self,
        ]
    }

    // V3'ün modelleri olduğu gibi kalır; V4 kendi kopyalarını tanımlar (varlık adları aynı).

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

    @Model
    final class InboxEntryRecord {
        // İçgörü id'si (`insight-YYYY-MM-<kind>`): aynı içgörü iki kez saklanmaz.
        @Attribute(.unique) var id: String
        var year: Int
        var month: Int
        var kind: String
        var title: String
        var body: String
        var createdAt: Date
        var isRead: Bool
        // Mezar taşı: silinen kayıt metni boşaltılmış olarak kalır, aynı id yeniden eklenmez.
        // (`isDeleted` adı PersistentModel'de zaten var.)
        var isTombstone: Bool

        init(
            id: String, year: Int, month: Int, kind: String, title: String, body: String,
            createdAt: Date, isRead: Bool, isTombstone: Bool
        ) {
            self.id = id
            self.year = year
            self.month = month
            self.kind = kind
            self.title = title
            self.body = body
            self.createdAt = createdAt
            self.isRead = isRead
            self.isTombstone = isTombstone
        }
    }
}

// Güncel şemanın kayıtları; depo ve eşleme kodu sürüm adını tekrar etmez.
typealias CardRecord = VademSchemaV4.CardRecord
typealias InstallmentRecord = VademSchemaV4.InstallmentRecord
typealias SubscriptionRecord = VademSchemaV4.SubscriptionRecord
typealias OneTimePaymentRecord = VademSchemaV4.OneTimePaymentRecord
typealias InboxEntryRecord = VademSchemaV4.InboxEntryRecord

/// The migration plan for the store. Every stage is lightweight, so every saved record is kept as is:
/// - V1 → V2: an attribute becomes optional and an optional attribute is added.
/// - V2 → V3: a new entity (one-time payments) is added; it starts empty.
/// - V3 → V4: a new entity (inbox entries) is added; it starts empty.
public enum VademMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [VademSchemaV1.self, VademSchemaV2.self, VademSchemaV3.self, VademSchemaV4.self]
    }

    public static var stages: [MigrationStage] { [migrateV1toV2, migrateV2toV3, migrateV3toV4] }

    // V1 → V2: `InstallmentRecord.cardID` isteğe bağlı olur, `paymentDay` eklenir (eski kayıtlarda nil).
    // Hesaplanan özellik: MigrationStage Sendable değil, statik saklı değer olamaz.
    static var migrateV1toV2: MigrationStage {
        .lightweight(fromVersion: VademSchemaV1.self, toVersion: VademSchemaV2.self)
    }

    // V2 → V3: yalnızca `OneTimePaymentRecord` varlığı eklenir; mevcut kayıtlar değişmez.
    static var migrateV2toV3: MigrationStage {
        .lightweight(fromVersion: VademSchemaV2.self, toVersion: VademSchemaV3.self)
    }

    // V3 → V4: yalnızca `InboxEntryRecord` varlığı eklenir; mevcut kayıtlar değişmez.
    static var migrateV3toV4: MigrationStage {
        .lightweight(fromVersion: VademSchemaV3.self, toVersion: VademSchemaV4.self)
    }
}
