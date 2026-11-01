import Foundation
import Testing
import VademCore
@testable import VademFeatures

// Tanıtım sayfası animasyon verisi (#259): döngü süresi, son durum, aşamalar.
@Suite("Onboarding animation")
struct OnboardingAnimationTests {

    private static let pages = OnboardingPage.allCases

    @Test("Cycle lasts 2 to 4 seconds on every page", arguments: pages)
    func cycleDuration(page: OnboardingPage) {
        let cycle = OnboardingAnimation.animation(for: page).cycleDuration
        #expect(cycle >= 2.0 && cycle <= 4.0)
    }

    @Test("Animation belongs to its page and has at least two stages", arguments: pages)
    func pageAndStages(page: OnboardingPage) {
        let animation = OnboardingAnimation.animation(for: page)
        #expect(animation.page == page)
        #expect(animation.stages.count >= 2)
        #expect(animation.stages == Array(0..<animation.steps.count))
    }

    @Test("End stage is the last stage", arguments: pages)
    func endStage(page: OnboardingPage) {
        let animation = OnboardingAnimation.animation(for: page)
        #expect(animation.endStage == animation.stages.last)
    }

    @Test("Step timings are positive", arguments: pages)
    func stepTimings(page: OnboardingPage) {
        for step in OnboardingAnimation.animation(for: page).steps {
            #expect(step.duration > 0)
            #expect(step.hold >= 0)
        }
    }

    @Test("Out-of-range stages are clamped", arguments: pages)
    func clamping(page: OnboardingPage) {
        let animation = OnboardingAnimation.animation(for: page)
        #expect(animation.step(at: -5) == animation.steps[0])
        #expect(animation.step(at: 999) == animation.steps[animation.endStage])
        #expect(animation.step(at: 1) == animation.steps[1])
    }

    @Test("Runs only when animated and visible", arguments: [
        (true, true, true),
        (true, false, false),
        (false, true, false),
        (false, false, false),
    ])
    func isRunning(animated: Bool, visible: Bool, expected: Bool) {
        #expect(OnboardingAnimation.isRunning(isAnimated: animated, isVisible: visible) == expected)
    }

    @Test("Illustration scales down at accessibility sizes")
    func scale() {
        let normal = OnboardingAnimation.scale(isAccessibilitySize: false)
        let large = OnboardingAnimation.scale(isAccessibilitySize: true)
        #expect(large < normal)
        #expect(large > 0 && normal <= 1)
    }

    // MARK: - Sayfa 1

    @Test("Monthly total counts up and stays at the end", arguments: [
        (0, Decimal(2400)), (1, Decimal(3600)), (2, Decimal(482_550) / 100), (3, Decimal(482_550) / 100),
    ])
    func monthlyTotal(stage: Int, expected: Decimal) {
        #expect(OnboardingAnimation.MonthlyTotal.total(at: stage) == Money(expected))
    }

    @Test("Payment row is shown only at the end state")
    func paymentRow() {
        let end = OnboardingAnimation.animation(for: .monthlyTotal).endStage
        #expect(OnboardingAnimation.MonthlyTotal.showsPaymentRow(at: end))
        #expect(!OnboardingAnimation.MonthlyTotal.showsPaymentRow(at: 0))
    }

    // MARK: - Sayfa 2

    @Test("Add steps advance amount, installments, card; plus pulses only at start")
    func addSteps() {
        typealias A = OnboardingAnimation.AddPayments
        #expect(A.plusPulses(at: 0))
        #expect(!A.plusPulses(at: 1))
        #expect(A.activeStep(at: 0) == nil)
        #expect(A.activeStep(at: 1) == .amount)
        #expect(A.activeStep(at: 2) == .installments)
        #expect(A.activeStep(at: 3) == .card)
        #expect(A.isDone(.amount, at: 2))
        #expect(!A.isDone(.amount, at: 1))
        #expect(!A.isDone(.card, at: 3))
    }

    @Test("Add page end state shows the card step active")
    func addEnd() {
        let end = OnboardingAnimation.animation(for: .addPayments).endStage
        #expect(OnboardingAnimation.AddPayments.activeStep(at: end) == .card)
        #expect(!OnboardingAnimation.AddPayments.plusPulses(at: end))
    }

    // MARK: - Sayfa 3

    @Test("Statement rows appear one per stage and clamp", arguments: [
        (-1, 0), (0, 0), (1, 1), (2, 2), (3, 3), (10, 3),
    ])
    func visibleRows(stage: Int, expected: Int) {
        #expect(OnboardingAnimation.StatementImport.visibleRowCount(at: stage) == expected)
    }

    @Test("Scan line moves from top to bottom", arguments: [
        (-1, 0.0), (0, 0.0), (3, 1.0), (10, 1.0),
    ])
    func scan(stage: Int, expected: Double) {
        #expect(OnboardingAnimation.StatementImport.scanProgress(at: stage) == expected)
    }

    @Test("Statement end state shows every row")
    func statementEnd() {
        let end = OnboardingAnimation.animation(for: .statementImport).endStage
        #expect(OnboardingAnimation.StatementImport.visibleRowCount(at: end)
            == OnboardingAnimation.StatementImport.rowAmounts.count)
    }

    // MARK: - Sayfa 4

    @Test("Bell rings mid-cycle and banner is in place at the end")
    func reminders() {
        typealias R = OnboardingAnimation.Reminders
        let end = OnboardingAnimation.animation(for: .reminders).endStage
        #expect(!R.bellRings(at: 0))
        #expect(R.bellRings(at: 1))
        #expect(!R.showsBanner(at: 0))
        #expect(R.showsBanner(at: end))
        #expect(!R.bellRings(at: end))
    }
}
