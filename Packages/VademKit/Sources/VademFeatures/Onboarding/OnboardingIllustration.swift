import SwiftUI

/// The decorative animated illustration above a walkthrough page's title (see ``OnboardingAnimation``).
///
/// It loops only while its page `isVisible` and motion is on; under Reduce Motion, `-ui-static-motion`
/// or off screen it is a single static frame of the end stage (no animator, no timer). It is laid out
/// at a fixed size with fixed text size and scaled down (more at accessibility text sizes), and is
/// hidden from VoiceOver: the page text carries the meaning.
@MainActor
struct OnboardingIllustration: View {
    let page: OnboardingPage
    let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let animation = OnboardingAnimation.animation(for: page)
        let isAnimated = Motion.isAnimated(reduceMotion: reduceMotion, staticMotionRequested: Motion.staticMotionRequested)
        let isRunning = OnboardingAnimation.isRunning(isAnimated: isAnimated, isVisible: isVisible)
        let scale = OnboardingAnimation.scale(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
        let width = OnboardingAnimation.designWidth
        let height = OnboardingAnimation.designHeight
        Group {
            if isRunning {
                // Döngü yalnızca görünen sayfada ve hareket açıkken kurulur.
                PhaseAnimator(animation.stages) { stage in
                    OnboardingIllustrationStage(page: page, stage: stage)
                } animation: { stage in
                    let step = animation.step(at: stage)
                    return .smooth(duration: step.duration).delay(step.hold)
                }
            } else {
                // Durağan kare: son aşama; zamanlayıcı yok, denetim boşta bir uygulama görür.
                OnboardingIllustrationStage(page: page, stage: animation.endStage)
            }
        }
        .frame(width: width, height: height)
        // Süsleme metni sabit boyutta çizilir; sayfa metni büyüdükçe çizim küçülür.
        .dynamicTypeSize(.large)
        .scaleEffect(scale)
        .frame(width: width * scale, height: height * scale)
        .accessibilityHidden(true)
    }
}

/// One stage of a page's illustration.
@MainActor
private struct OnboardingIllustrationStage: View {
    let page: OnboardingPage
    let stage: Int

    var body: some View {
        switch page {
        case .monthlyTotal: MonthlyTotalIllustration(stage: stage)
        case .addPayments: AddPaymentsIllustration(stage: stage)
        case .statementImport: StatementImportIllustration(stage: stage)
        case .reminders: RemindersIllustration(stage: stage)
        }
    }
}

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: 24) {
            ForEach(OnboardingPage.allCases) { page in
                OnboardingIllustration(page: page, isVisible: true)
            }
        }
        .padding(24)
    }
    .background(Color.vademBackground)
}
#endif
