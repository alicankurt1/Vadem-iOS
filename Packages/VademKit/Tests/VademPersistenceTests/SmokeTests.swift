import Testing
@testable import VademPersistence

// Modülün bağlandığını ve App Group kimliğinin beklenen biçimde olduğunu gösterir.
@Suite("Persistence smoke")
struct SmokeTests {
    @Test("App Group identifier uses the group. prefix and the bundle ID")
    func appGroupIdentifier() {
        #expect(VademPersistence.appGroupIdentifier == "group.com.alicankurt.Vadem")
    }
}
