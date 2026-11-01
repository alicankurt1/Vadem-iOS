import SwiftUI
import VademCore

/// Page 1: the hero panel's monthly total counts up, then a payment row slides into place.
@MainActor
struct MonthlyTotalIllustration: View {
    let stage: Int

    private typealias Sample = OnboardingAnimation.MonthlyTotal

    var body: some View {
        let showsRow = Sample.showsPaymentRow(at: stage)
        VStack(spacing: 12) {
            HeroPanel(
                title: String(localized: "This month", bundle: .module),
                total: Sample.total(at: stage),
                paid: Sample.paid
            )
            // Satır yerini baştan tutar; yalnızca saydamlığı ve kayması değişir (çizim zıplamaz).
            SurfaceCard {
                PaymentRow(
                    day: Sample.rowDay,
                    title: String(localized: "Phone", bundle: .module),
                    subtitle: String(localized: "Installment", bundle: .module),
                    amount: Sample.rowAmount,
                    dueTitle: String(localized: "Tomorrow", bundle: .module),
                    dueKind: .soon
                )
            }
            .opacity(showsRow ? 1 : 0)
            .offset(y: showsRow ? 0 : 24)
        }
    }
}
