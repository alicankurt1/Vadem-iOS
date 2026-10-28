// Kalıcılık katmanı: SwiftData sadece bu modülde kullanılır. Domain tipleri VademCore'da
// struct olarak kalır; burada @Model kayıtları ve VademCore'daki repository protokollerinin
// SwiftData uygulamaları yer alır.
import Foundation
import SwiftData

/// Paylaşılan ayarlar.
public enum VademPersistence {
    /// Uygulama, widget ve App Intents'in aynı veriyi okuduğu App Group.
    /// `Config/Vadem.entitlements` ile aynı olmalı.
    public static let appGroupIdentifier = "group.com.alicankurt.Vadem"

    /// Where the store lives.
    public enum Storage: Sendable, Hashable {
        /// The app's store, in the ``VademPersistence/appGroupIdentifier`` container.
        case appGroup
        /// A store in memory only; starts empty and is lost with the container.
        case inMemory
        /// A store at the given file URL (e.g. a temporary file in tests).
        case file(URL)
    }

    /// Creates a container for ``VademSchemaV3`` with ``VademMigrationPlan``; a V1 or V2 store is migrated.
    ///
    /// CloudKit is always off: data never leaves the device.
    public static func makeContainer(storage: Storage) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VademSchemaV3.self)
        let configuration = switch storage {
        case .appGroup:
            ModelConfiguration(schema: schema, groupContainer: .identifier(appGroupIdentifier), cloudKitDatabase: .none)
        case .inMemory:
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        case .file(let url):
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: VademMigrationPlan.self, configurations: configuration)
    }
}
