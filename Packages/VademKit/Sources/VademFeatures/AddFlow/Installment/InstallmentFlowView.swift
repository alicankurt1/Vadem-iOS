import SwiftUI
import VademCore

/// The quick installment flow inside the Add sheet: amount keypad → count chips → card →
/// first month chips → optional title → summary with one Save button (``InstallmentFlowViewModel``).
///
/// Each step is a ``FlowStepContainer`` (identifiers `flow.*`); chips advance on tap, the amount
/// and title steps (and an open "Other" stepper) use Continue. Back on the first step calls `onExit`
/// (the sheet shows its three buttons again); a successful save calls `onSaved` (the sheet closes).
/// "New card" opens the ``AddCardView`` and chooses the saved card.
/// Identifiers: `addInstallmentFlow.count.chip.<i>` (presets, then Other), `addInstallmentFlow.countStepper`,
/// `addInstallmentFlow.month.chip.<i>` (This month, Next month, Other), `addInstallmentFlow.monthStepper`,
/// `addInstallmentFlow.titleField`, `addInstallmentFlow.title.chip.<i>`, `addInstallmentFlow.titleTooLong`,
/// `addInstallmentFlow.skip`, `addInstallmentFlow.summary.<amount|count|card|firstMonth|paymentDay|title>`,
/// `addInstallmentFlow.changePaymentDay`, `addInstallmentFlow.paymentDayStepper`, `addInstallmentFlow.save`,
/// `addInstallmentFlow.failure`; the card step reuses `cardPicker.*`, the keypad `keypad.*`.
/// No continuous animations, so it is idle under `-ui-static-motion`.
@MainActor
public struct InstallmentFlowView: View {
    /// The launch argument that opens Home with the Add sheet already running this flow (UI check).
    public nonisolated static let launchArgument = "-ui-add-installment-flow"

    @Bindable private var model: InstallmentFlowViewModel
    private let onExit: () -> Void
    private let onClose: () -> Void
    private let onSaved: () -> Void
    // "Yeni kart" ile açılan kart formunun modeli; nil iken sayfa kapalı.
    @State private var addCardModel: AddCardViewModel?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates the flow for `model`. `onExit` runs for Back on the first step, `onClose` for the
    /// close button and `onSaved` after a successful save.
    public init(
        model: InstallmentFlowViewModel,
        onExit: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onSaved: @escaping () -> Void
    ) {
        self.model = model
        self.onExit = onExit
        self.onClose = onClose
        self.onSaved = onSaved
    }

    public var body: some View {
        FlowStepContainer(
            title: model.title(of: model.steps.current),
            stepNumber: model.steps.number,
            stepCount: model.steps.count,
            onBack: back,
            onClose: onClose,
            canContinue: model.canContinue,
            onContinue: model.showsContinue ? { move { model.continueFromCurrentStep() } } : nil
        ) {
            if let message = model.failureMessage {
                FormFailureRow(message: message)
                    .accessibilityIdentifier("addInstallmentFlow.failure")
            }
            stepContent
        }
        // Yeni kart kaydedilince kartlar yenilenir, kart seçilir ve sonraki adıma geçilir.
        .sheet(item: $addCardModel) { addCardModel in
            AddCardView(model: addCardModel) { card in
                move { model.selectAddedCard(card) }
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.steps.current {
        case .amount:
            AmountKeypad(state: $model.keypad)
        case .count:
            countStep
        case .card:
            CardPickerStep(cards: model.cards, selection: model.cardID) { id in
                move { model.chooseCard(id) }
            } onAddCard: {
                addCardModel = model.makeAddCardModel()
            }
        case .firstMonth:
            monthStep
        case .title:
            titleStep
        case .summary:
            summaryStep
        }
    }

    // MARK: Adımlar

    private var countStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            ChoiceChips(
                options: InstallmentFlowViewModel.countPresets.map { .init(value: InstallmentCountChoice.preset($0), title: String($0)) }
                    + [.init(value: .other, title: Self.otherTitle)],
                selection: model.countChoice, identifierPrefix: "addInstallmentFlow.count"
            ) { choice in
                move { model.chooseCount(choice) }
            }
            if model.isEnteringOtherCount {
                // "Diğer": desteklenen aralıkta (1–36) basit bir sayaç.
                Stepper(
                    value: Binding(get: { model.count ?? InstallmentFlowViewModel.otherCountStart }, set: { model.setOtherCount($0) }),
                    in: InstallmentPlan.supportedCounts
                ) {
                    Text("Installments: \(model.count ?? InstallmentFlowViewModel.otherCountStart)", bundle: .module)
                        .foregroundStyle(Color.vademTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(Color.vademSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityIdentifier("addInstallmentFlow.countStepper")
            }
        }
    }

    private var monthStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            ChoiceChips(
                options: [
                    .init(value: InstallmentMonthChoice.thisMonth, title: String(localized: "This month", bundle: .module)),
                    .init(value: .nextMonth, title: String(localized: "Next month", bundle: .module)),
                    .init(value: .other, title: Self.otherTitle),
                ],
                // Yan yana dizilince büyük yazıda kırpılıyordu (a11y denetimi); sayı adımı gibi alt alta.
                selection: model.monthChoice, identifierPrefix: "addInstallmentFlow.month", stacked: true
            ) { choice in
                move { model.chooseMonth(choice) }
            }
            if model.monthChoice == .other {
                // "Diğer": bugünün çevresindeki aylar arasında bir sayaç.
                Stepper(
                    value: Binding(get: { model.firstMonthIndex }, set: { model.setFirstMonthIndex($0) }),
                    in: 0...max(model.firstMonthOptions.count - 1, 0)
                ) {
                    Text(model.title(of: model.firstMonth))
                        .foregroundStyle(Color.vademTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(Color.vademSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityIdentifier("addInstallmentFlow.monthStepper")
            }
        }
    }

    private var titleStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Dikey eksen: büyük yazı boyutlarında metin kırpılmaz, sarılır.
            TextField(
                String(localized: "Title", bundle: .module),
                text: $model.title, prompt: Text("e.g. Laptop", bundle: .module), axis: .vertical
            )
                #if os(iOS)
                .textInputAutocapitalization(.sentences)
                #endif
                .foregroundStyle(Color.vademTextPrimary)
                .padding(16)
                .frame(minHeight: 52)
                .background(Color.vademSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier("addInstallmentFlow.titleField")
            if model.isTitleTooLong {
                Text("Use at most \(InstallmentItem.maxTitleLength) characters.", bundle: .module)
                    .font(.footnote)
                    .foregroundStyle(Color.vademTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("addInstallmentFlow.titleTooLong")
            }
            ChoiceChips(
                options: InstallmentFlowViewModel.quickTitles.map { .init(value: $0, title: $0) },
                selection: InstallmentFlowViewModel.quickTitles.contains(model.title) ? model.title : nil,
                identifierPrefix: "addInstallmentFlow.title"
            ) { title in
                move { model.chooseTitle(title) }
            }
            // Başlık isteğe bağlı: atlanırsa varsayılan başlık ("Taksit") kaydedilir.
            Button {
                move { model.skipTitle() }
            } label: {
                Text("Skip", bundle: .module)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.vademBrand)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("addInstallmentFlow.skip")
        }
    }

    private var summaryStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            SurfaceCard {
                summaryRow(
                    label: String(localized: "Total amount", bundle: .module),
                    value: AmountText.format(Money(model.keypad.amount ?? 0)),
                    identifier: "amount"
                )
                summaryRow(
                    label: String(localized: "Installments", bundle: .module),
                    value: model.count.map { String($0) } ?? "",
                    identifier: "count"
                )
                summaryRow(label: String(localized: "Card", bundle: .module), value: model.cardTitle, identifier: "card")
                summaryRow(
                    label: String(localized: "First due month", bundle: .module),
                    value: model.title(of: model.firstMonth),
                    identifier: "firstMonth"
                )
                paymentDayRow
                summaryRow(label: String(localized: "Title", bundle: .module), value: model.resolvedTitle, identifier: "title")
            }
            saveButton
        }
    }

    // Etiket üstte, değer altta: her yazı boyutunda sarılır, kırpılmaz.
    private func summaryRow(label: String, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Color.vademTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.vademTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("addInstallmentFlow.summary.\(identifier)")
    }

    // Ödeme günü zorunlu bir adım değil: varsayılan karttan veya bugünden gelir, kartsızken "Değiştir" ile açılır.
    private var paymentDayRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryRow(
                label: String(localized: "Payment day", bundle: .module),
                value: String(localized: "Day \(model.effectivePaymentDay)", bundle: .module),
                identifier: "paymentDay"
            )
            if model.canChangePaymentDay {
                if model.isChangingPaymentDay {
                    Stepper(
                        value: Binding(get: { model.paymentDay }, set: { model.changePaymentDay(to: $0) }),
                        in: InstallmentItem.supportedPaymentDays
                    ) {
                        Text("Paid on day \(model.paymentDay)", bundle: .module)
                            .foregroundStyle(Color.vademTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("addInstallmentFlow.paymentDayStepper")
                } else {
                    Button {
                        move { model.beginChangingPaymentDay() }
                    } label: {
                        Text("Change", bundle: .module)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.vademBrand)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("addInstallmentFlow.changePaymentDay")
                }
            }
        }
    }

    private var saveButton: some View {
        Button {
            if model.save() { onSaved() }
        } label: {
            Text("Save", bundle: .module)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.vademOnAccent)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.vademAccent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!model.canSave)
        // Pasif durum saydamlıkla gösterilir; metin aynı kalır.
        .opacity(model.canSave ? 1 : 0.5)
        .accessibilityIdentifier("addInstallmentFlow.save")
    }

    // MARK: Yardımcılar

    private static var otherTitle: String { String(localized: "Other", bundle: .module) }

    // İlk adımda geri, akıştan çıkar (sayfa üç düğmeye döner).
    private func back() {
        if model.steps.isFirst {
            onExit()
        } else {
            move { model.goBack() }
        }
    }

    // Adım geçişi; Reduce Motion veya -ui-static-motion açıkken animasyonsuz.
    private func move(_ change: () -> Void) {
        withAnimation(Motion.animation(Motion.quick, reduceMotion: reduceMotion)) {
            change()
        }
    }
}

#if DEBUG
#Preview {
    let model = HomeSampleData.makeViewModel()
    return InstallmentFlowView(
        model: model.makeInstallmentFlowModel(), onExit: {}, onClose: {}, onSaved: {}
    )
}
#endif
