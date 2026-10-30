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

// Sekme geçişi, kademeli giriş ve çubuk dolumu (#210).
@Suite("Motion transitions")
struct MotionTransitionTests {

    // MARK: - Animation gating

    @Test("Animation is nil when motion is off", arguments: [
        (true, false), (false, true), (true, true),
    ])
    func animationNilWhenOff(reduceMotion: Bool, staticMotion: Bool) {
        #expect(Motion.animation(Motion.quick, reduceMotion: reduceMotion, staticMotionRequested: staticMotion) == nil)
    }

    @Test("Animation is returned when motion is on")
    func animationWhenOn() {
        #expect(Motion.animation(Motion.quick, reduceMotion: false, staticMotionRequested: false) == Motion.quick)
    }

    // MARK: - Tab switch phases

    @Test("Visible phase is the settled look")
    func visiblePhase() {
        let phase = Motion.TabSwitchPhase.visible
        #expect(phase.opacity == 1)
        #expect(phase.blurRadius == 0)
        #expect(phase.scale == 1)
    }

    @Test("Leaving phase fades out with blur and slight scale-down")
    func leavingPhase() {
        let phase = Motion.TabSwitchPhase.leaving
        #expect(phase.opacity == 0)
        #expect(phase.blurRadius > 0)
        #expect(phase.scale < 1 && phase.scale > 0.9)
    }

    @Test("Entering phase is invisible without blur or scale so only opacity animates in")
    func enteringPhase() {
        let phase = Motion.TabSwitchPhase.entering
        #expect(phase.opacity == 0)
        #expect(phase.blurRadius == 0)
        #expect(phase.scale == 1)
    }

    @Test("Tab fade-out is no slower than fade-in and both are short")
    func tabDurations() {
        #expect(Motion.tabOutDuration > 0)
        #expect(Motion.tabInDuration >= Motion.tabOutDuration)
        #expect(Motion.tabOutDuration + Motion.tabInDuration < 0.6)
    }

    // MARK: - Stagger

    @Test("Entry order is header, then hero, then list")
    func entryOrder() {
        #expect(Motion.EntryOrder.allCases == [.header, .hero, .list])
        #expect(Motion.EntryOrder.header < .hero)
        #expect(Motion.EntryOrder.hero < .list)
    }

    @Test("Header enters without delay")
    func headerNoDelay() {
        #expect(Motion.entryDelay(order: .header) == 0)
    }

    @Test("Delays strictly increase from header to list")
    func delaysIncrease() {
        let header = Motion.entryDelay(order: .header)
        let hero = Motion.entryDelay(order: .hero)
        let list = Motion.entryDelay(order: .list)
        #expect(header < hero)
        #expect(hero < list)
        #expect(Motion.entryStagger > 0)
    }

    @Test("Whole stagger stays short")
    func staggerShort() {
        let total = Motion.entryDelay(order: .list) + Motion.entryDuration
        #expect(total < 1.0)
    }

    // MARK: - Entry state

    @Test("Entry state per motion and entered flags", arguments: [
        (false, true, Motion.EntryState.hidden),
        (true, true, Motion.EntryState.settled),
        (false, false, Motion.EntryState.settled),
        (true, false, Motion.EntryState.settled),
    ])
    func entryState(hasEntered: Bool, isAnimated: Bool, expected: Motion.EntryState) {
        #expect(Motion.entryState(hasEntered: hasEntered, isAnimated: isAnimated) == expected)
    }

    @Test("Settled state is fully shown and hidden state is not")
    func settledVsHidden() {
        #expect(Motion.EntryState.settled.opacity == 1)
        #expect(Motion.EntryState.settled.offsetY == 0)
        #expect(Motion.EntryState.settled.scale == 1)
        #expect(Motion.EntryState.hidden.opacity == 0)
        #expect(Motion.EntryState.hidden.offsetY > 0)
        #expect(Motion.EntryState.hidden.scale < 1)
    }

    // MARK: - Progress fill

    @Test("Fill fraction per flags", arguments: [
        (0.0, false, true, 0.0),
        (0.75, false, true, 0.0),
        (0.75, true, true, 0.75),
        (0.75, false, false, 0.75),
        (0.75, true, false, 0.75),
        (1.0, false, false, 1.0),
        (0.0, false, false, 0.0),
        (1.0, false, true, 0.0),
    ])
    func fillFraction(value: Double, hasAppeared: Bool, isAnimated: Bool, expected: Double) {
        #expect(Motion.fillFraction(value, hasAppeared: hasAppeared, isAnimated: isAnimated) == expected)
    }
}
