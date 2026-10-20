import Foundation
import SwiftData

/// The first shipped store schema: cards, installments and subscriptions as flat records.
///
/// Never change this schema in place; a change adds `VademSchemaV2` and a migration stage.
public enum VademSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [CardRecord.self, InstallmentRecord.self, SubscriptionRecord.self]
    }

    // Kayıtlar şema içinde tanımlanır; V2 geldiğinde V1'in modelleri olduğu gibi kalır.
    // İlişki yok: öğeler kartı yalnızca `cardID` ile tutar, kurallar depoda uygulanır.
    // Tutar, ondalık metin olarak saklanır (Double değil); ay, yıl ve ay numarası olarak.

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
        var cardID: UUID
        var total: String
        var count: Int
        var firstYear: Int
        var firstMonth: Int

        init(id: UUID, title: String, cardID: UUID, total: String, count: Int, firstYear: Int, firstMonth: Int) {
            self.id = id
            self.title = title
            self.cardID = cardID
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
typealias CardRecord = VademSchemaV1.CardRecord
typealias InstallmentRecord = VademSchemaV1.InstallmentRecord
typealias SubscriptionRecord = VademSchemaV1.SubscriptionRecord

/// The migration plan for the store. V1 is the only version, so there are no stages yet.
public enum VademMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [VademSchemaV1.self] }

    public static var stages: [MigrationStage] { [] }
}
