import Testing
import VademFeatures

@Suite("Motion")
struct MotionTests {

    // Hareket yalnızca ne Reduce Motion ne de UI kontrolünün statik hareket isteği açıkken var.
    @Test("Animates only when neither Reduce Motion nor static motion is on", arguments: [
        (false, false, true),
        (true, false, false),
        (false, true, false),
        (true, true, false),
    ])
    func isAnimated(reduceMotion: Bool, staticMotion: Bool, expected: Bool) {
        #expect(Motion.isAnimated(reduceMotion: reduceMotion, staticMotionRequested: staticMotion) == expected)
    }

    @Test("Static motion launch argument matches the UI check harness")
    func staticMotionArgument() {
        #expect(Motion.staticMotionArgument == "-ui-static-motion")
    }
}
