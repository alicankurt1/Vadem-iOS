import SwiftUI
import VademCore

/// The one-time payment add flow in quick steps inside a ``FlowStepContainer``:
/// amount (keypad) → Today / Tomorrow / Pick a date → card → optional title → summary with one Save button
/// (``OneTimeFlowViewModel``).
///
/// Chips and cards advance on tap; the amount and title steps (and an open "Pick a date") use Continue.
/// Back on the first step calls `onExit` (hidden when `nil`; the Add sheet shows its three buttons again);
/// close calls `onClose` and a successful save `onSaved` (both dismiss the presenting sheet when `nil`).
/// "New card" opens the ``AddCardView`` and chooses the saved card.
/// No continuous animations; step changes are not animated under Reduce Motion or `-ui-static-motion`.
/// Identifiers: shared step ones (`flow.*`, `keypad.*`, `cardPicker.*`),
/// `oneTimeFlow.date.chip.<index>` (Today, Tomorrow, Pick a date), `oneTimeFlow.monthStepper`,
/// `oneTimeFlow.dayStepper` (a ``DayPickerRow``, sheet `oneTimeFlow.dayStepper.sheet`, `.picker`, `.done`),
/// `oneTimeFlow.titleField`, `oneTimeFlow.title.chip.<index>`,
/// `oneTimeFlow.titleTooLong`, `oneTimeFlow.skip`, `oneTimeFlow.summary`,
/// `oneTimeFlow.summary.<amount|date|card|title>`, `oneTimeFlow.failure`, `oneTimeFlow.save`.
@MainActor
public struct OneTimeFlowView: View {
    @Bindable private var model: OneTimeFlowViewModel
    private let onExit: (() -> Void)?
    private let onClose: (() -> Void)?
    private let onSaved: (() -> Void)?
    // "Yeni kart" ile açılan kart formunun modeli; nil iken sayfa kapalı.
    @State private var addCardModel: AddCardViewModel?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates the flow for `model`. `onExit` runs for Back on the first step (no back button when `nil`);
    /// `onClose` for the close button and `onSaved` after a successful save (each dismisses when `nil`).
    public init(
        model: OneTimeFlowViewModel,
        onExit: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onSaved: (() -> Void)? = nil
    ) {
        self.model = model
        self.onExit = onExit
        self.onClose = onClose
        self.onSaved = onSaved
    }

    public var body: some View {
        FlowStepContainer(
            title: model.title(of: model.step),
            stepNumber: model.steps.number,
            stepCount: model.steps.count,
            onBack: backAction,
            onClose: { close() },
            canContinue: model.canContinue,
            onContinue: model.showsContinue ? { move { model.continueFromCurrentStep() } } : nil
        ) {
            stepContent
        }
        // Yeni kart kaydedilince listeye eklenir, seçilir ve sonraki adıma geçilir.
        .sheet(item: $addCardModel) { addCardModel in
            AddCardView(model: addCardModel) { card in
                move { model.selectAddedCard(card) }
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .amount:
            AmountKeypad(state: $model.keypad)
        case .date:
            dateStep
        case .card:
            CardPickerStep(cards: model.cards, selection: model.cardID) { id in
                move { model.chooseCard(id) }
            } onAddCard: {
                addCardModel = model.makeAddCardModel()
            }
        case .title:
            titleStep
        case .summary:
            summaryStep
        }
    }

    // MARK: Adımlar

    private var dateStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            ChoiceChips(
                options: [
                    .init(value: OneTimeDateChoice.today, title: String(localized: "Today", bundle: .module)),
                    .init(value: .tomorrow, title: String(localized: "Tomorrow", bundle: .module)),
                    .init(value: .pick, title: String(localized: "Pick a date", bundle: .module)),
                ],
                // Taksit akışının ay adımı gibi alt alta: büyük yazıda yan yana dizilim kırpılıyordu.
                selection: model.dateChoice, identifierPrefix: "oneTimeFlow.date", stacked: true
            ) { choice in
                move { model.chooseDate(choice) }
            }
            if model.dateChoice == .pick {
                // "Tarih seç": bugünün çevresindeki aylar ve ayın günleri: ay için sayaç, gün için gün seçici satırı.
                VStack(alignment: .leading, spacing: 12) {
                    Stepper(
                        value: Binding(get: { model.dueMonthIndex }, set: { model.setDueMonthIndex($0) }),
                        in: 0...max(model.monthOptions.count - 1, 0)
                    ) {
                        Text(model.title(of: model.dueMonth))
                            .foregroundStyle(Color.vademTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("oneTimeFlow.monthStepper")
                    // Kimlik eski adıyla kalır: testler için sabit bir çapa.
                    DayPickerRow(
                        title: String(localized: "Due day", bundle: .module),
                        day: Binding(get: { model.dueDay }, set: { model.setDueDay($0) }),
                        range: 1...model.dueMonth.numberOfDays, identifier: "oneTimeFlow.dayStepper"
                    )
                }
                .padding(16)
                .background(Color.vademSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private var titleStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Dikey eksen: büyük yazı boyutlarında metin kırpılmaz, sarılır.
            TextField(
                String(localized: "Title", bundle: .module),
                text: $model.title, prompt: Text("e.g. Dentist", bundle: .module), axis: .vertical
            )
                #if os(iOS)
                .textInputAutocapitalization(.sentences)
                #endif
                .foregroundStyle(Color.vademTextPrimary)
                .padding(16)
                .frame(minHeight: 52)
                .background(Color.vademSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier("oneTimeFlow.titleField")
            if model.isTitleTooLong {
                Text("Use at most \(OneTimePaymentItem.maxTitleLength) characters.", bundle: .module)
                    .font(.footnote)
                    .foregroundStyle(Color.vademTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("oneTimeFlow.titleTooLong")
            }
            ChoiceChips(
                options: OneTimeFlowViewModel.quickTitles.map { .init(value: $0, title: $0) },
                selection: OneTimeFlowViewModel.quickTitles.contains(model.title) ? model.title : nil,
                identifierPrefix: "oneTimeFlow.title"
            ) { title in
                move { model.chooseTitle(title) }
            }
            // Başlık isteğe bağlı: atlanırsa varsayılan başlık ("Ödeme") kaydedilir.
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
            .accessibilityHint(Text("Saves it as \(OneTimeFlowViewModel.defaultTitle)", bundle: .module))
            .accessibilityIdentifier("oneTimeFlow.skip")
        }
    }

    private var summaryStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let message = model.failureMessage {
                SurfaceCard {
                    FormFailureRow(message: message)
                        .accessibilityIdentifier("oneTimeFlow.failure")
                }
            }
            SurfaceCard {
                summaryRow(
                    label: String(localized: "Amount", bundle: .module),
                    value: AmountText.format(Money(model.keypad.amount ?? 0)),
                    identifier: "amount"
                )
                summaryRow(label: String(localized: "Due date", bundle: .module), value: model.dueDateText, identifier: "date")
                summaryRow(label: String(localized: "Card", bundle: .module), value: model.cardTitle, identifier: "card")
                summaryRow(label: String(localized: "Title", bundle: .module), value: model.resolvedTitle, identifier: "title")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("oneTimeFlow.summary")
            saveButton
        }
    }

    // Etiket üstte, değer altta: her yazı boyutunda sarılır, kırpılmaz; VoiceOver ikisini birlikte okur.
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
        .accessibilityIdentifier("oneTimeFlow.summary.\(identifier)")
    }

    private var saveButton: some View {
        Button {
            if model.save() {
                if let onSaved { onSaved() } else { dismiss() }
            }
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
        .accessibilityIdentifier("oneTimeFlow.save")
    }

    // MARK: Yardımcılar

    // İlk adımda geri, akıştan çıkar (varsa); sonraki adımlarda bir önceki adıma döner.
    private var backAction: (() -> Void)? {
        if model.steps.isFirst {
            return onExit
        }
        return { move { model.goBack() } }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
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
    let home = HomeSampleData.makeViewModel()
    return OneTimeFlowView(model: home.makeOneTimeFlowModel())
}
#endif
