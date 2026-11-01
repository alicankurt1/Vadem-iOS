import SwiftUI
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

    // MARK: - Tab switch

    @Test("Settled look is fully opaque and unblurred")
    func settledLook() {
        #expect(Motion.TabSwitchState.settled.opacity == 1)
        #expect(Motion.TabSwitchState.settled.blur == 0)
    }

    @Test("Same tab is settled", arguments: AppTab.allCases)
    func sameTabSettled(tab: AppTab) {
        #expect(Motion.tabSwitchStart(from: tab, to: tab) == .settled)
    }

    // Boş kare olmaz: başlangıç görünümü hiçbir geçişte görünmez olmaz.
    @Test("Start look never drops the content to invisible", arguments: AppTab.allCases, AppTab.allCases)
    func neverBlank(from: AppTab, to: AppTab) {
        let start = Motion.tabSwitchStart(from: from, to: to)
        #expect(start.opacity > 0.5)
        #expect(start.opacity <= 1)
    }

    // Yön yok: her farklı sekme çifti aynı sakin çapraz geçişi kullanır.
    @Test("Every pair of different tabs uses the same cross-fade look", arguments: AppTab.allCases, AppTab.allCases)
    func sameLookForEveryPair(from: AppTab, to: AppTab) {
        guard from != to else { return }
        let start = Motion.tabSwitchStart(from: from, to: to)
        #expect(start == Motion.tabSwitchStart(from: to, to: from))
        #expect(start.opacity < 1)
        #expect(start.opacity == Motion.tabSwitchStartOpacity)
        #expect(start.blur == Motion.tabSwitchStartBlur)
    }

    @Test("Start blur is very slight")
    func startBlurSlight() {
        #expect(Motion.tabSwitchStartBlur > 0)
        #expect(Motion.tabSwitchStartBlur <= 4)
    }

    @Test("Tab switch duration is short (about 0.2 to 0.3 s)")
    func tabSwitchTuning() {
        #expect(Motion.tabSwitchDuration >= 0.2)
        #expect(Motion.tabSwitchDuration <= 0.3)
    }

    // Arka plan tonu içerikle aynı sürede değişir (senkron).
    @Test("Ambient tint follows the tab switch timing")
    func ambientTintInSync() {
        #expect(Motion.ambientTint == Animation.easeOut(duration: Motion.tabSwitchDuration))
    }

    // MARK: - Entry only at launch

    @Test("Entry plays only on the launch tab", arguments: AppTab.allCases, AppTab.allCases)
    func entryPlaysOnlyOnLaunchTab(tab: AppTab, launchTab: AppTab) {
        #expect(Motion.entryPlays(tab: tab, launchTab: launchTab) == (tab == launchTab))
    }

    @Test("Exactly one tab plays the entry for a given launch tab", arguments: AppTab.allCases)
    func exactlyOneTabPlays(launchTab: AppTab) {
        let playing = AppTab.allCases.filter { Motion.entryPlays(tab: $0, launchTab: launchTab) }
        #expect(playing == [launchTab])
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
