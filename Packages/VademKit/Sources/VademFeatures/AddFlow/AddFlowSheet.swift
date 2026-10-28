import SwiftUI

/// The bottom sheet Home opens from Add: "What do you want to add?" and three large buttons,
/// Installment, Subscription and Payment (``AddFlowKind``).
///
/// Picking a kind that ``AddFlowKind/opensExistingForm`` calls `onSelect`; the presenter closes
/// the sheet and opens that form. Payment runs inside the sheet: for now one "coming soon"
/// ``FlowStepContainer`` step whose back button returns to the three buttons.
/// The content scrolls; at accessibility text sizes the sheet opens at full height.
/// Identifiers: `add.sheet.title`, `add.sheet.close`, `add.sheet.<kind>` (``AddFlowKind/accessibilityIdentifier``),
/// `add.sheet.comingSoon`. No continuous animations, so it is idle under `-ui-static-motion`.
@MainActor
public struct AddFlowSheet: View {
    /// The launch argument that opens Home with this sheet already presented (UI check).
    public nonisolated static let launchArgument = "-ui-add-sheet"

    private let onSelect: (AddFlowKind) -> Void
    // Sayfanın içinde süren akış; nil iken üç düğme görünür.
    @State private var inlineKind: AddFlowKind?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates the sheet; `onSelect` gets the kinds that open an existing form.
    public init(onSelect: @escaping (AddFlowKind) -> Void) {
        self.onSelect = onSelect
    }

    public var body: some View {
        Group {
            if inlineKind == .payment {
                paymentPlaceholder
            } else {
                chooser
            }
        }
        .background(Color.vademBackground.ignoresSafeArea())
        // Büyük yazıda yarım yükseklik dar kalır; sayfa doğrudan tam boy açılır.
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func select(_ kind: AddFlowKind) {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("add.sheet.title")
                        .padding(.bottom, 4)
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

    // Büyük düğme: simge, başlık ve altında kısa açıklama; VoiceOver başlığı etiket, açıklamayı ipucu olarak okur.
    private func kindButton(_ kind: AddFlowKind) -> some View {
        Button {
            select(kind)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: kind.systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.vademBrand)
                    .frame(minWidth: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.vademTextPrimary)
                    Text(kind.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.vademTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.vademTextSecondary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(Color.vademSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
        .accessibilityHint(kind.subtitle)
        .accessibilityAddTraits(.isButton)
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
            VStack(alignment: .leading, spacing: 8) {
                Text("Coming soon", bundle: .module)
                    .font(.headline)
                    .foregroundStyle(Color.vademTextPrimary)
                Text("Adding a one-off payment is coming soon.", bundle: .module)
                    .font(.body)
                    .foregroundStyle(Color.vademTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
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
