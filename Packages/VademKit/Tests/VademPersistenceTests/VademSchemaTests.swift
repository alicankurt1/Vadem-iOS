import SwiftData
import Testing
import VademPersistence

// Şema ilk günden sürümlü: V1 = 1.0.0, V2 = 2.0.0, V3 = 3.0.0; göç planı V1 → V2 → V3 aşamalarını listeler.
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

    @Test("Schema V2 has version 2.0.0 and lists the three record models")
    func versionV2() {
        #expect(VademSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        #expect(VademSchemaV2.models.count == 3)
    }

    @Test("Migration plan lists V1, V2 then V3 and has two stages")
    func migrationPlan() {
        let schemas = VademMigrationPlan.schemas
        #expect(schemas.count == 3)
        #expect(schemas.first.map { $0 == VademSchemaV1.self } == true)
        #expect(schemas.last.map { $0 == VademSchemaV3.self } == true)
        #expect(schemas.first?.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(schemas.last?.versionIdentifier == Schema.Version(3, 0, 0))
        #expect(VademMigrationPlan.stages.count == 2)
    }

    @Test("Container schema is version 3.0.0", arguments: [StorageKind.inMemory, .file])
    @MainActor
    func containerSchemaVersion(kind: StorageKind) throws {
        try TemporaryStore.with { url in
            let container = try VademPersistence.makeContainer(storage: kind.storage(url))
            #expect(container.schema.version == Schema.Version(3, 0, 0))
            #expect(container.schema.entities.count == 4)
        }
    }
}
