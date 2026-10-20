import SwiftData
import Testing
import VademPersistence

// Şema ilk günden sürümlü: V1 = 1.0.0 ve göç planı yalnızca V1'i listeler.
@Suite("Vadem schema")
struct VademSchemaTests {
    @Test("Schema V1 has version 1.0.0")
    func versionIdentifier() {
        #expect(VademSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    }

    @Test("Schema V1 lists the three record models")
    func modelCount() {
        #expect(VademSchemaV1.models.count == 3)
    }

    @Test("Migration plan lists only VademSchemaV1 and has no stages")
    func migrationPlan() {
        let schemas = VademMigrationPlan.schemas
        #expect(schemas.count == 1)
        #expect(schemas.first.map { $0 == VademSchemaV1.self } == true)
        #expect(schemas.first?.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(VademMigrationPlan.stages.isEmpty)
    }

    @Test("Container schema is version 1.0.0", arguments: [StorageKind.inMemory, .file])
    @MainActor
    func containerSchemaVersion(kind: StorageKind) throws {
        try TemporaryStore.with { url in
            let container = try VademPersistence.makeContainer(storage: kind.storage(url))
            #expect(container.schema.version == Schema.Version(1, 0, 0))
            #expect(container.schema.entities.count == 3)
        }
    }
}
