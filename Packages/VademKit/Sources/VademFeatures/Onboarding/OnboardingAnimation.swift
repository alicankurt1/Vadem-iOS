import Foundation
import VademCore

/// The looping animation of one walkthrough illustration: its stages (`0..<steps.count`), how long
/// each one takes, the end state and the made-up sample values each page shows at a stage.
///
/// Pure data, no SwiftUI: the illustration views draw a stage, a `PhaseAnimator` cycles through
/// ``stages``. When the animation does not run (``isRunning(isAnimated:isVisible:)`` is `false`:
/// Reduce Motion, `-ui-static-motion` or the page is off screen) the view shows ``endStage`` only.
public struct OnboardingAnimation: Sendable, Equatable {
    /// The move into one stage.
    public struct Step: Sendable, Equatable {
        /// Seconds the previous stage is held before the move starts.
        public let hold: Double
        /// Seconds the move into this stage takes.
        public let duration: Double

        /// Creates a step that waits `hold` seconds, then moves in `duration` seconds.
        public init(hold: Double, duration: Double) {
            self.hold = hold
            self.duration = duration
        }
    }

    /// The page this animation belongs to.
    public let page: OnboardingPage
    /// One step per stage; step `0` is the move from the end stage back to the start (the loop).
    public let steps: [Step]

    /// The stages in play order: `0, 1, …, steps.count - 1`.
    public var stages: [Int] { Array(steps.indices) }

    /// The last stage: the settled end state shown when the animation does not run.
    public var endStage: Int { steps.count - 1 }

    /// Seconds of one full loop: every step's hold plus its duration.
    public var cycleDuration: Double {
        steps.reduce(0) { $0 + $1.hold + $1.duration }
    }

    /// The step into `stage`; out-of-range stages are clamped.
    public func step(at stage: Int) -> Step {
        steps[min(max(stage, 0), endStage)]
    }

    /// The animation of `page`; every page loops gently in 2–4 seconds.
    public static func animation(for page: OnboardingPage) -> OnboardingAnimation {
        switch page {
        case .monthlyTotal:
            // Toplam iki adımda sayarak artar, sonra ödeme satırı kayarak gelir.
            return OnboardingAnimation(page: page, steps: [
                Step(hold: 1.0, duration: 0.3),
                Step(hold: 0.2, duration: 0.6),
                Step(hold: 0.1, duration: 0.6),
                Step(hold: 0.2, duration: 0.5),
            ])
        case .addPayments:
            // ＋ nabız atar, sonra hızlı adımlar sırayla ilerler: tutar → taksit → kart.
            return OnboardingAnimation(page: page, steps: [
                Step(hold: 0.9, duration: 0.35),
                Step(hold: 0.25, duration: 0.4),
                Step(hold: 0.35, duration: 0.4),
                Step(hold: 0.35, duration: 0.4),
            ])
        case .statementImport:
            // Tarama çizgisi belgeyi geçerken taksit satırları birer birer belirir.
            return OnboardingAnimation(page: page, steps: [
                Step(hold: 0.9, duration: 0.3),
                Step(hold: 0.2, duration: 0.6),
                Step(hold: 0.1, duration: 0.6),
                Step(hold: 0.1, duration: 0.6),
            ])
        case .reminders:
            // Zil sallanır, ardından bildirim kayarak iner.
            return OnboardingAnimation(page: page, steps: [
                Step(hold: 1.0, duration: 0.35),
                Step(hold: 0.2, duration: 0.4),
                Step(hold: 0.9, duration: 0.5),
            ])
        }
    }

    /// Whether the loop runs: only when motion is on (``Motion/isAnimated(reduceMotion:staticMotionRequested:)``)
    /// and the page is the visible one. Otherwise the view shows ``endStage`` with no animation or timer.
    public static func isRunning(isAnimated: Bool, isVisible: Bool) -> Bool {
        isAnimated && isVisible
    }

    // MARK: - Çizim boyutu

    /// Width (points) the illustrations are laid out in, before ``scale(isAccessibilitySize:)``.
    public static let designWidth: Double = 300
    /// Height (points) the illustrations are laid out in, before ``scale(isAccessibilitySize:)``.
    public static let designHeight: Double = 270

    /// The illustration's scale: `0.85` normally, `0.6` at accessibility text sizes so the page text has room.
    ///
    /// The illustration's own text stays at a fixed size (it is decorative and hidden from VoiceOver).
    public static func scale(isAccessibilitySize: Bool) -> Double {
        isAccessibilitySize ? 0.6 : 0.85
    }

    // MARK: - Sayfa 1: aylık toplam

    /// Sample values of the monthly-total page (made up).
    public enum MonthlyTotal {
        /// The paid amount shown in the hero panel.
        public static let paid = Money(1_200)
        /// The amount of the payment row that slides in.
        public static let rowAmount = Money(Decimal(122_550) / 100)
        /// The day of month of the payment row.
        public static let rowDay = 15

        /// The hero total at `stage`: counts up `₺2.400,00 → ₺3.600,00 → ₺4.825,50`, then stays.
        public static func total(at stage: Int) -> Money {
            switch stage {
            case ..<1: Money(2_400)
            case 1: Money(3_600)
            default: Money(Decimal(482_550) / 100)
            }
        }

        /// Whether the payment row is in place at `stage` (the last stage only).
        public static func showsPaymentRow(at stage: Int) -> Bool {
            stage >= 3
        }
    }

    // MARK: - Sayfa 2: ekleme

    /// Sample values of the add-payment page (made up).
    public enum AddPayments {
        /// One quick step of the Add sheet, in order.
        public enum QuickStep: Int, CaseIterable, Sendable {
            /// "How much?"
            case amount
            /// The number of installments.
            case installments
            /// Which card.
            case card
        }

        /// The amount shown in the amount step.
        public static let amount = Money(2_400)
        /// The number of installments shown in the installments step.
        public static let installmentCount = 6
        /// The last four digits of the card shown in the card step.
        public static let cardLastDigits = "4242"

        /// Whether the ＋ button is pulsed (enlarged) at `stage`: only at the start.
        public static func plusPulses(at stage: Int) -> Bool {
            stage <= 0
        }

        /// The active quick step at `stage`: none at the start, then amount, installments, card.
        public static func activeStep(at stage: Int) -> QuickStep? {
            QuickStep(rawValue: stage - 1)
        }

        /// Whether `step` is done (checked) at `stage`: every step before the active one.
        public static func isDone(_ step: QuickStep, at stage: Int) -> Bool {
            step.rawValue < stage - 1
        }
    }

    // MARK: - Sayfa 3: ekstreden aktarma

    /// Sample values of the statement-import page (made up).
    public enum StatementImport {
        /// The installment amounts read from the statement, one row each.
        public static let rowAmounts: [Money] = [
            Money(Decimal(45_000) / 100),
            Money(Decimal(128_990) / 100),
            Money(Decimal(31_250) / 100),
        ]

        /// How many rows are shown (with their checkmarks) at `stage`: one more per stage, up to all.
        public static func visibleRowCount(at stage: Int) -> Int {
            min(max(stage, 0), rowAmounts.count)
        }

        /// Where the scan line is at `stage`, from `0` (top of the document) to `1` (bottom).
        public static func scanProgress(at stage: Int) -> Double {
            let last = rowAmounts.count
            return Double(min(max(stage, 0), last)) / Double(last)
        }
    }

    // MARK: - Sayfa 4: hatırlatmalar

    /// Sample values of the reminders page (made up).
    public enum Reminders {
        /// The amount in the notification banner.
        public static let amount = Money(Decimal(122_550) / 100)

        /// Whether the bell rings (its symbol effect is active) at `stage`: the middle stage only.
        public static func bellRings(at stage: Int) -> Bool {
            stage == 1
        }

        /// Whether the notification banner is in place at `stage` (the last stage).
        public static func showsBanner(at stage: Int) -> Bool {
            stage >= 2
        }
    }
}
