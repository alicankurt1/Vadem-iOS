import SwiftUI
import VademCore

/// Page 2: the ＋ button pulses, then the Add sheet's quick steps advance: amount → installments → card.
@MainActor
struct AddPaymentsIllustration: View {
    let stage: Int

    private typealias Sample = OnboardingAnimation.AddPayments

    var body: some View {
        VStack(alignment: .trailing, spacing: 16) {
            SurfaceCard {
                ForEach(Sample.QuickStep.allCases, id: \.self) { step in
                    stepRow(step)
                }
            }
            plusButton
        }
    }

    // Tek hızlı adım: durum simgesi, adı ve seçilen değer.
    private func stepRow(_ step: Sample.QuickStep) -> some View {
        let isActive = Sample.activeStep(at: stage) == step
        let isDone = Sample.isDone(step, at: stage)
        return HStack(spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : (isActive ? "largecircle.fill.circle" : "circle"))
                .font(.title3)
                .foregroundStyle(isDone ? Color.vademPaid : (isActive ? Color.vademBrand : Color.vademTextSecondary))
            title(step)
                .font(.body.weight(isActive ? .semibold : .regular))
                .foregroundStyle(Color.vademTextPrimary)
            Spacer(minLength: 8)
            value(step)
                .font(.body.weight(.semibold))
                .foregroundStyle(isActive || isDone ? Color.vademTextPrimary : Color.vademTextSecondary)
        }
        .padding(.vertical, 2)
        // Etkin adımın çevresinde marka renginde ince bir çerçeve.
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.vademBrand, lineWidth: 2)
                .padding(-6)
                .opacity(isActive ? 1 : 0)
        }
    }

    @ViewBuilder
    private func title(_ step: Sample.QuickStep) -> some View {
        switch step {
        case .amount: Text("Amount", bundle: .module)
        case .installments: Text("Installments", bundle: .module)
        case .card: Text("Card", bundle: .module)
        }
    }

    @ViewBuilder
    private func value(_ step: Sample.QuickStep) -> some View {
        switch step {
        case .amount: AmountText(Sample.amount)
        case .installments: Text(verbatim: "\(Sample.installmentCount)×").monospacedDigit()
        case .card: Text(verbatim: "•••• \(Sample.cardLastDigits)").monospacedDigit()
        }
    }

    // Ana ekrandaki ＋ düğmesinin benzeri; başta büyüyüp nabız atar.
    private var plusButton: some View {
        Image(systemName: "plus")
            .font(.title2.weight(.bold))
            .foregroundStyle(Color.vademOnAccent)
            .frame(width: 56, height: 56)
            .background(Color.vademAccent, in: .circle)
            .scaleEffect(Sample.plusPulses(at: stage) ? 1.15 : 1)
    }
}
