import Testing
@testable import VademCore

// Zincirin çalıştığını gösteren tek smoke test.
@Suite("Smoke")
struct SmokeTests {
    @Test("Core module is linked and versioned")
    func coreVersion() {
        #expect(VademCore.version == "0.1.0")
    }
}
