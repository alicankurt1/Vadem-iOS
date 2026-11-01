import SwiftUI
import VademCore

/// Page 3: a scan line passes over a statement; the installments found appear one by one with checkmarks.
@MainActor
struct StatementImportIllustration: View {
    let stage: Int

    private typealias Sample = OnboardingAnimation.StatementImport

    private static let documentWidth: CGFloat = 96
    private static let documentHeight: CGFloat = 128

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            document
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Sample.rowAmounts.indices, id: \.self) { index in
                    row(index)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Satırları çizgilerle gösterilen belge ve üzerinden geçen tarama çizgisi.
    private var document: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let travel = Self.documentHeight - 20
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<6, id: \.self) { line in
                Capsule()
                    .fill(Color.vademSeparator)
                    .frame(width: line.isMultiple(of: 2) ? 64 : 48, height: 6)
            }
        }
        .padding(14)
        .frame(width: Self.documentWidth, height: Self.documentHeight, alignment: .topLeading)
        .background(Color.vademSurface, in: shape)
        .overlay { shape.stroke(Color.vademSeparator, lineWidth: 1) }
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.vademBrand)
                .frame(height: 3)
                .padding(.horizontal, 6)
                .offset(y: 8 + travel * Sample.scanProgress(at: stage))
        }
    }

    // Bulunan taksit: onay işareti, adı ve tutarı; yerini baştan tutar, belirerek gelir.
    private func row(_ index: Int) -> some View {
        let isShown = index < Sample.visibleRowCount(at: stage)
        return HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.vademPaid)
            VStack(alignment: .leading, spacing: 0) {
                Text("Installment", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(Color.vademTextSecondary)
                AmountText(Sample.rowAmounts[index])
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.vademTextPrimary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .vademGlassSurface(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(isShown ? 1 : 0)
        .offset(x: isShown ? 0 : 16)
    }
}
