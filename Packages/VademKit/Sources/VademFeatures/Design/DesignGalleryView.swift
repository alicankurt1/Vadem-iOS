import SwiftUI
import VademCore

/// Shows every color token, chip kind, card style and sample amounts in one screen,
/// so the UI check can verify contrast and layout. Opened with the `-ui-gallery` launch argument.
@MainActor
public struct DesignGalleryView: View {
    // Tutarlar Double'dan değil, tam Decimal'den kurulur.
    @State private var animatedAmount = Money(Decimal(123_456) / 100)

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Design gallery")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.vademTextPrimary)
                    .accessibilityAddTraits(.isHeader)

                section("Colors", id: "gallery.colors") {
                    ForEach(ColorToken.allCases, id: \.self) { token in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(token.color)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.vademSeparator)
                                }
                                .accessibilityHidden(true)
                            Text(token.rawValue)
                                .font(.body)
                                .foregroundStyle(Color.vademTextPrimary)
                        }
                    }
                }

                section("Chips", id: "gallery.chips") {
                    DueChip("Today", kind: .today)
                    DueChip("In 3 days", kind: .soon)
                    DueChip("Later", kind: .later)
                    Label("Paid", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.vademPaid)
                }

                section("Amounts", id: "gallery.amounts") {
                    ForEach([Decimal(0), Decimal(123_456) / 100, -5, 1_000_000], id: \.self) { amount in
                        AmountText(Money(amount))
                            .font(.title2)
                            .foregroundStyle(Color.vademTextPrimary)
                    }
                    AmountText(animatedAmount)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(Color.vademBrand)
                    Button("Add ₺100") {
                        animatedAmount = animatedAmount + Money(100)
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.vademTextPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .vademGlass()
                }

                section("Cards", id: "gallery.cards") {
                    ForEach(CardStyle.allCases, id: \.self) { style in
                        CardFaceView(title: style.name, subtitle: "Due on the 15th", style: style)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.vademBackground.ignoresSafeArea())
    }

    // Bölüm başlığı + içerik; başlık VoiceOver'da başlık olarak okunur.
    // Kimlik başlıkta: UI testi bölüme bu sabit kimlikle kaydırır.
    private func section(_ title: String, id: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.vademTextSecondary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(id)
            content()
        }
    }
}

#Preview("Light") {
    DesignGalleryView()
}

#Preview("Dark") {
    DesignGalleryView()
        .preferredColorScheme(.dark)
}
