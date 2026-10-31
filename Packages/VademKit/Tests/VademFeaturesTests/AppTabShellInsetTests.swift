import Testing
import VademFeatures

@Suite("AppTabShell bottom inset")
struct AppTabShellInsetTests {
    @Test("Gap between last row and floating bar is positive")
    @MainActor func barGapIsPositive() {
        #expect(AppTabShell.barGap > 0)
    }
}
