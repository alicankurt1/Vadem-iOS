import SwiftUI
import VademCore

/// Shows every color token, chip kind, card style and sample amounts in one screen,
/// so the UI check can verify contrast and layout. Opened with the `-ui-gallery` launch argument.
@MainActor
public struct DesignGalleryView: View {
    // Tutarlar Double'dan değil, tam Decimal'den kurulur.
    @State private var animatedAmount = Money(Decimal(123_456) / 100)

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    public init() {}

    // "Ekle" düğmesinin eklediği tutar.
    nonisolated static let addedAmount = Money(100)

    /// The "Add ₺100" button's accessibility label, without the `₺` symbol: "Add 100,00 Türk lirası".
    nonisolated static var addButtonAccessibilityLabel: String {
        "Add " + AmountText.spokenLabel(addedAmount)
    }

    public var body: some View {
        // NavigationStack üst kenarı verir: kaydırılan içerik saatin altına girmez.
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    section("Colors", id: "gallery.colors") {
                        ForEach(ColorToken.allCases, id: \.self) { token in
                            tokenRow(token)
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
                            animatedAmount = animatedAmount + Self.addedAmount
                        }
                        // VoiceOver ve denetim "₺" sembolü yerine okunabilir tutarı alır.
                        .accessibilityLabel(Self.addButtonAccessibilityLabel)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.vademTextPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .vademGlass()
                    }

                    section("Hero", id: "gallery.hero") {
                        HeroPanel(title: "This month", total: Money(Decimal(482_550) / 100), paid: Money(1_200)) {
                            Button {} label: { Label("Add", systemImage: "plus") }
                                .buttonStyle(.heroPill)
                            Button {} label: { Label("Calendar", systemImage: "calendar") }
                                .buttonStyle(.heroPill)
                        }
                    }

                    section("Rows", id: "gallery.rows") {
                        SurfaceCard {
                            PaymentRow(
                                day: 22, title: "Rent", subtitle: "Everyday card",
                                amount: Money(15_000), dueTitle: "Overdue", dueKind: .overdue
                            )
                            PaymentRow(
                                day: 24, title: "Netflix", subtitle: "Subscription",
                                amount: Money(Decimal(22_999) / 100), dueTitle: "Today", dueKind: .today
                            )
                            PaymentRow(
                                day: 27, title: "Laptop", subtitle: "Everyday card · 3/12",
                                amount: Money(Decimal(208_333) / 100), dueTitle: "In 3 days", dueKind: .soon
                            )
                            PaymentRow(
                                day: 5, title: "Phone", subtitle: "Travel card · 7/9",
                                amount: Money(1_000_000), dueTitle: "Later", dueKind: .later
                            )
                        }
                    }

                    section("Pills", id: "gallery.pills") {
                        Button {} label: { Label("Add", systemImage: "plus") }
                            .buttonStyle(.heroPill)
                        Button("Calendar") {}
                            .buttonStyle(.heroPill)
                    }

                    section("Cards", id: "gallery.cards") {
                        ForEach(CardStyle.allCases, id: \.self) { style in
                            CardFaceView(title: style.name, subtitle: "Due on the 15th", style: style)
                                .accessibilityIdentifier("gallery.card.\(style.rawValue)")
                        }
                    }
                }
                // 20 pt yan boşluk: ekranın sol kenarında her zaman arka plan rengi kalır.
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.vademBackground.ignoresSafeArea())
            .navigationTitle("Design gallery")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            // iOS 26 çubuğu altından geçen koyu kartlara uyum sağlamasın: renk şeması ve arka plan
            // ekranın şemasına sabitlenir (açıkta açık zemin + mürekkep başlık, koyuda koyu token'lar).
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .toolbarBackground(Color(Color.vademBackground.resolve(in: environment)), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
        }
    }

    // Token adı her zaman ekran arka planında, örnek kutunun yanında (erişilebilir boyutlarda altında);
    // asla kutunun üstüne çizilmez.
    private func tokenRow(_ token: ColorToken) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(token.color)
                .frame(width: 44, height: 44)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.vademTextSecondary.opacity(0.4))
                }
                .accessibilityHidden(true)
            Text(token.rawValue)
                .font(.body)
                .foregroundStyle(Color.vademTextPrimary)
                .background(Color.vademBackground)
        }
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
