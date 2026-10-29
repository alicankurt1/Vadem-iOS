import SwiftUI
import VademCore

/// The subscription add flow in quick steps inside a ``FlowStepContainer``:
/// amount (keypad) → Monthly / Yearly → card → optional title → summary with one Save button.
///
/// Choosing a chip or a card advances on its own; the keypad continues with Continue (amount above zero).
/// The summary shows every choice, the renewal day (today unless changed under "Change") and Save,
/// which saves through ``SubscriptionFlowViewModel/save()`` and closes the sheet.
/// No continuous animations; step changes are not animated under Reduce Motion or `-ui-static-motion`.
/// Identifiers: shared step ones (`flow.*`, `keypad.*`, `cardPicker.*`), `subscriptionFlow.period.chip.<index>`,
/// `subscriptionFlow.title.chip.<index>`, `subscriptionFlow.skip`, `subscriptionFlow.summary`,
/// `subscriptionFlow.summary.<amount|period|card|title|renewalDay>`, `subscriptionFlow.changeRenewalDay`,
/// `subscriptionFlow.renewalDay` (a ``DayPickerRow``, sheet `subscriptionFlow.renewalDay.sheet`, `.picker`, `.done`), `subscriptionFlow.failure`, `subscriptionFlow.save`.
@MainActor
public struct SubscriptionFlowView: View {
    @State private var model: SubscriptionFlowViewModel
    // "Yeni kart" ile açılan kart formunun modeli; nil iken sayfa kapalı.
    @State private var addCardModel: AddCardViewModel?
    private let makeAddCardModel: () -> AddCardViewModel
    private let onExit: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates the flow for `model`. `makeAddCardModel` backs "New card"; `onExit` is the back button
    /// of the first step (hidden when `nil`). Save and close dismiss the presenting sheet.
    public init(
        model: SubscriptionFlowViewModel,
        makeAddCardModel: @escaping () -> AddCardViewModel,
        onExit: (() -> Void)? = nil
    ) {
        _model = State(initialValue: model)
        self.makeAddCardModel = makeAddCardModel
        self.onExit = onExit
    }

    public var body: some View {
        FlowStepContainer(
            title: title(of: model.step),
            stepNumber: model.steps.number,
            stepCount: model.steps.count,
            onBack: backAction,
            onClose: { dismiss() },
            canContinue: model.canContinueAmount,
            onContinue: model.step == .amount ? { move { model.advance() } } : nil
        ) {
            switch model.step {
            case .amount:
                AmountKeypad(state: $model.keypad)
            case .period:
                ChoiceChips(
                    options: AddSubscriptionViewModel.periods.map {
                        .init(value: $0, title: AddSubscriptionViewModel.title(of: $0))
                    },
                    selection: model.form.period, identifierPrefix: "subscriptionFlow.period"
                ) { period in
                    move { model.choose(period: period) }
                }
            case .card:
                CardPickerStep(cards: model.cards, selection: model.form.cardID) { id in
                    move { model.choose(cardID: id) }
                } onAddCard: {
                    addCardModel = makeAddCardModel()
                }
            case .title:
                titleStep
            case .summary:
                summaryStep
            }
        }
        .sheet(item: $addCardModel) { addCardModel in
            AddCardView(model: addCardModel) { card in
                // Yeni kart listeye eklenir ve seçilir.
                model.didAddCard(card)
            }
        }
    }

    // İlk adımda geri, akıştan çıkar (varsa); sonraki adımlarda bir önceki adıma döner.
    private var backAction: (() -> Void)? {
        if model.steps.isFirst {
            return onExit
        }
        return { move { model.goBack() } }
    }

    // Adım geçişi; Reduce Motion veya -ui-static-motion açıkken animasyonsuz.
    private func move(_ change: () -> Void) {
        withAnimation(Motion.animation(Motion.quick, reduceMotion: reduceMotion)) {
            change()
        }
    }

    private func title(of step: SubscriptionFlowStep) -> String {
        switch step {
        case .amount: String(localized: "How much?", bundle: .module)
        case .period: String(localized: "How often?", bundle: .module)
        case .card: String(localized: "Which card?", bundle: .module)
        case .title: String(localized: "What is it?", bundle: .module)
        case .summary: String(localized: "Ready to save?", bundle: .module)
        }
    }

    // Başlık isteğe bağlı: hızlı çiplerden biri ya da Geç (boş başlık varsayılan başlıkla kaydedilir).
    private var titleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChoiceChips(
                options: SubscriptionFlowViewModel.quickTitles.map { .init(value: $0, title: $0) },
                selection: model.form.title, identifierPrefix: "subscriptionFlow.title"
            ) { title in
                move { model.choose(title: title) }
            }
            Button {
                move { model.skipTitle() }
            } label: {
                Text("Skip", bundle: .module)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.vademBrand)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Saves it as \(SubscriptionFlowViewModel.defaultTitle)", bundle: .module))
            .accessibilityIdentifier("subscriptionFlow.skip")
        }
    }

    private var summaryStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let message = model.form.failureMessage {
                SurfaceCard {
                    FormFailureRow(message: message)
                        .accessibilityIdentifier("subscriptionFlow.failure")
                }
            }
            SurfaceCard {
                summaryRow(
                    String(localized: "Amount", bundle: .module),
                    value: AmountText.format(Money(model.keypad.amount ?? 0)),
                    identifier: "amount"
                )
                summaryRow(
                    String(localized: "Repeats", bundle: .module),
                    value: AddSubscriptionViewModel.title(of: model.form.period),
                    identifier: "period"
                )
                summaryRow(String(localized: "Card", bundle: .module), value: model.cardTitle, identifier: "card")
                summaryRow(String(localized: "Title", bundle: .module), value: model.effectiveTitle, identifier: "title")
                renewalDayRow
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("subscriptionFlow.summary")
            saveButton
        }
    }

    // Etiket ve değer alt alta: her yazı boyutunda sarılır, kırpılmaz; VoiceOver ikisini birlikte okur.
    private func summaryRow(_ label: String, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.vademTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.vademTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("subscriptionFlow.summary.\(identifier)")
    }

    // Yenileme günü bugündür; "Değiştir" bağlantısı gün seçiciyi açar.
    @ViewBuilder
    private var renewalDayRow: some View {
        if model.isChangingRenewalDay {
            DayPickerRow(
                title: String(localized: "Renewal day", bundle: .module), day: Bindable(model.form).renewalDay,
                range: Subscription.supportedRenewalDays, identifier: "subscriptionFlow.renewalDay"
            )
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Renews on day \(model.form.renewalDay)", bundle: .module)
                    .font(.body)
                    .foregroundStyle(Color.vademTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("subscriptionFlow.summary.renewalDay")
                Button {
                    model.isChangingRenewalDay = true
                } label: {
                    Text("Change", bundle: .module)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.vademBrand)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Changes the renewal day", bundle: .module))
                .accessibilityIdentifier("subscriptionFlow.changeRenewalDay")
            }
        }
    }

    private var saveButton: some View {
        Button {
            if model.save() {
                dismiss()
            }
        } label: {
            Text("Save", bundle: .module)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.vademOnAccent)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.vademAccent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!model.canSave)
        // Pasif durum saydamlıkla gösterilir; metin aynı kalır.
        .opacity(model.canSave ? 1 : 0.5)
        .accessibilityIdentifier("subscriptionFlow.save")
    }
}

#if DEBUG
#Preview {
    let home = HomeSampleData.makeViewModel()
    return SubscriptionFlowView(
        model: SubscriptionFlowViewModel(form: home.makeAddSubscriptionModel(), lastUsedCardID: nil),
        makeAddCardModel: home.makeAddCardModel
    )
}
#endif
