import SwiftUI
import VademCore

/// Page 4: the bell rings (SF Symbols effect), then a payment notification banner slides in.
@MainActor
struct RemindersIllustration: View {
    let stage: Int

    private typealias Sample = OnboardingAnimation.Reminders

    var body: some View {
        let showsBanner = Sample.showsBanner(at: stage)
        VStack(spacing: 28) {
            banner
                .opacity(showsBanner ? 1 : 0)
                .offset(y: showsBanner ? 0 : -24)
            // Sembol efekti yalnızca çalma aşamasında etkin; durağan karede hiç başlamaz.
            Image(systemName: "bell.fill")
                .font(.system(size: 72, weight: .regular))
                .foregroundStyle(Color.vademBrand)
                .symbolEffect(.wiggle, options: .repeat(.continuous), isActive: Sample.bellRings(at: stage))
        }
    }

    // Kilit ekranı bildirimi benzeri: uygulama simgesi, ad, ileti ve tutar.
    private var banner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.title3)
                .foregroundStyle(Color.vademOnAccent)
                .frame(width: 40, height: 40)
                .background(Color.vademAccent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Vadem", bundle: .module)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.vademTextPrimary)
                Text("Payment due tomorrow", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(Color.vademTextPrimary)
                AmountText(Sample.amount)
                    .font(.subheadline)
                    .foregroundStyle(Color.vademTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .vademGlassSurface(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
