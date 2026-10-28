import SwiftUI

/// The bottom sheet Home opens from Add: "What do you want to add?" and three large buttons,
/// Installment, Subscription and Payment (``AddFlowKind``).
///
/// Picking a kind that ``AddFlowKind/opensExistingForm`` calls `onSelect`; the presenter closes
/// the sheet and opens that form. Subscription runs inside the sheet as a ``SubscriptionFlowView``
/// (back on its first step returns to the three buttons). Payment runs inside the sheet: for now one "coming soon"
/// ``FlowStepContainer`` step whose back button returns to the three buttons.
/// The content scrolls and the sheet always opens at full height: with `presentationDetents`
/// (medium or even large only) the accessibility audit reported every multi-word text as clipped.
/// Each kind button reads its visible title and subtitle together (no custom label).
/// Identifiers: `add.sheet.title`, `add.sheet.close`, `add.sheet.<kind>` (``AddFlowKind/accessibilityIdentifier``),
/// `add.sheet.comingSoon`. No continuous animations, so it is idle under `-ui-static-motion`.
@MainActor
public struct AddFlowSheet: View {
    /// The launch argument that opens Home with this sheet already presented (UI check).
    public nonisolated static let launchArgument = "-ui-add-sheet"

    private let onSelect: (AddFlowKind) -> Void
    private let makeSubscriptionFlow: (() -> SubscriptionFlowViewModel)?
    private let makeAddCardModel: (() -> AddCardViewModel)?
    // Sayfada süren abonelik akışının modeli; Abonelik seçilince kurulur.
    @State private var subscriptionFlow: SubscriptionFlowViewModel?
    // Sayfanın içinde süren akış; nil iken üç düğme görünür.
    @State private var inlineKind: AddFlowKind?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates the sheet; `onSelect` gets the kinds that open an existing form.
    ///
    /// `makeSubscriptionFlow` and `makeAddCardModel` back the subscription flow; without them
    /// Subscription goes to `onSelect` like a kind that opens an existing form.
    public init(
        onSelect: @escaping (AddFlowKind) -> Void,
        makeSubscriptionFlow: (() -> SubscriptionFlowViewModel)? = nil,
        makeAddCardModel: (() -> AddCardViewModel)? = nil
    ) {
        self.onSelect = onSelect
        self.makeSubscriptionFlow = makeSubscriptionFlow
        self.makeAddCardModel = makeAddCardModel
    }

    public var body: some View {
        Group {
            if inlineKind == .payment {
                paymentPlaceholder
            } else if inlineKind == .subscription, let subscriptionFlow, let makeAddCardModel {
                SubscriptionFlowView(model: subscriptionFlow, makeAddCardModel: makeAddCardModel) {
                    withAnimation(Motion.animation(Motion.quick, reduceMotion: reduceMotion)) {
                        inlineKind = nil
                    }
                }
            } else {
                chooser
            }
        }
        .background(Color.vademBackground.ignoresSafeArea())
    }

    private func select(_ kind: AddFlowKind) {
        if kind == .subscription {
            // Fabrika verilmediyse abonelik eski formu açar.
            guard let makeSubscriptionFlow, makeAddCardModel != nil else {
                onSelect(kind)
                return
            }
            // Her seçimde yeni akış: önceki yarım kalan girişler taşınmaz.
            subscriptionFlow = makeSubscriptionFlow()
        }
        if kind.opensExistingForm {
            onSelect(kind)
        } else {
            withAnimation(Motion.animation(Motion.quick, reduceMotion: reduceMotion)) {
                inlineKind = kind
            }
        }
    }

    private var chooser: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.vademTextPrimary)
                        // En az 44 pt dokunma alanı.
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close", bundle: .module))
                .accessibilityIdentifier("add.sheet.close")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What do you want to add?", bundle: .module)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.vademTextPrimary)
                        // Metin her boyutta tam yüksekliğini alır, sarılır; asla kırpılmaz.
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("add.sheet.title")
                    ForEach(AddFlowKind.allCases) { kind in
                        kindButton(kind)
                    }
                }
                // 20 pt yan boşluk: sol kenarda her zaman arka plan rengi kalır.
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    // Büyük düğme: simge, başlık ve altında kısa açıklama; VoiceOver ikisini birlikte okur.
    private func kindButton(_ kind: AddFlowKind) -> some View {
        Button {
            select(kind)
        } label: {
            // Erişilebilir yazı boyutlarında simge metnin üstünde ve ok gizli: metin tüm genişliği
            // alır, kelimeler ortadan bölünmez. AnyLayout metinlerin kimliğini korur.
            let stacked = dynamicTypeSize.isAccessibilitySize
            let layout = stacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
            layout {
                Image(systemName: kind.systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.vademBrand)
                    .frame(minWidth: 32, alignment: .leading)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.vademTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(kind.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.vademTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .multilineTextAlignment(.leading)
                if !stacked {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.vademTextSecondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(Color.vademSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Etiket görünen başlık + açıklamanın kendisi: özel etiket görünen metinden farklı olunca
        // denetim metni "kırpılmış" sayıyor.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(kind.accessibilityIdentifier)
    }

    // Ödeme akışı henüz yok: akış kabuğunda tek adımlık "yakında" ekranı.
    private var paymentPlaceholder: some View {
        FlowStepContainer(
            title: AddFlowKind.payment.title, stepNumber: 1, stepCount: 1,
            onBack: {
                withAnimation(Motion.animation(Motion.quick, reduceMotion: reduceMotion)) {
                    inlineKind = nil
                }
            },
            onClose: { dismiss() }
        ) {
            // İki metin ayrı öğe: birleşik etiket ikinci metnin çerçevesiyle ölçülüp "kırpılmış" sayılıyordu.
            VStack(alignment: .leading, spacing: 8) {
                Text("Coming soon", bundle: .module)
                    .font(.headline)
                    .foregroundStyle(Color.vademTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Adding a one-off payment is coming soon.", bundle: .module)
                    .font(.body)
                    .foregroundStyle(Color.vademTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .multilineTextAlignment(.leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("add.sheet.comingSoon")
        }
    }
}

#if DEBUG
#Preview {
    Color.vademBackground
        .sheet(isPresented: .constant(true)) {
            AddFlowSheet { _ in }
        }
}
#endif
