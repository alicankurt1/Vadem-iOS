import Testing
@testable import VademFeatures

@Suite("AppTabShell bottom inset")
struct AppTabShellInsetTests {
    @Test("Gap between last row and floating bar is positive")
    func barGapIsPositive() {
        #expect(AppTabShell.barGap > 0)
    }
}
