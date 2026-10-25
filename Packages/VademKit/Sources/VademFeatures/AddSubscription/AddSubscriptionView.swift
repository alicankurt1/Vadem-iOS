import SwiftUI
import VademCore

/// The add-subscription form, shown as a sheet from Home: title, amount, optional card,
/// period, renewal day and first charge month.
///
/// Each invalid field shows its error below it (once touched); Save stays disabled while
/// the form is invalid. No continuous animations, so it is idle under `-ui-static-motion`.
/// Identifiers: `addSubscription.<field>` for fields (`title`, `amount`, `card`, `period`,
/// `renewalDay`, `firstMonth`), `addSubscription.<field>.error` for errors,
/// `addSubscription.save`, `addSubscription.cancel`, `addSubscription.failure`; pushed lists
/// use `addSubscription.options` and `addSubscription.option.<index>`.
/// In edit mode (``AddSubscriptionViewModel/isEditing``) the title is "Edit subscription" and a
/// Delete button (`addSubscription.delete`) asks for confirmation (`addSubscription.delete.confirm`,
/// `addSubscription.delete.cancel`) before deleting.
@MainActor
public struct AddSubscriptionView: View {
    /// The launch argument that opens Home with this form already presented (UI check).
    public nonisolated static let launchArgument = "-ui-add-subscription"
    /// The launch argument that, with ``launchArgument``, also shows every field's error.
    public nonisolated static let errorsLaunchArgument = "-ui-add-subscription-errors"
    /// The launch argument that opens Home with the first subscription of the month in this form, in edit mode (UI check).
    public nonisolated static let editLaunchArgument = "-ui-edit-subscription"

    @State private var model: AddSubscriptionViewModel
    // Silme onayı açık mı.
    @State private var isConfirmingDelete = false
    // Odaktaki metin alanı; satırın boş yerine dokununca o satırın alanı odaklanır.
    @FocusState private var focusedField: SubscriptionDraft.Field?
    @State private var choice: Choice?
    private let onSaved: () -> Void
    private let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    /// Creates the form for `model`; `onSaved` runs after a successful save and `onDeleted`
    /// after a successful delete, before the sheet closes.
    public init(
        model: AddSubscriptionViewModel, onSaved: @escaping () -> Void = {}, onDeleted: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: model)
        self.onSaved = onSaved
        self.onDeleted = onDeleted
    }

    public var body: some View {
        NavigationStack {
            FormScroll {
                if let message = model.failureMessage {
                    FormCard {
                        FormFailureRow(message: message)
                            .accessibilityIdentifier("addSubscription.failure")
                    }
                }
                // Tüm alanlar tek kartta, ince çizgilerle ayrılmış satırlar olarak durur.
                FormCard {
                    field(.title) {
                        TextField(
                            String(localized: "Title", bundle: .module),
                            text: $model.title, prompt: Text("e.g. Music", bundle: .module)
                        )
                            #if os(iOS)
                            .textInputAutocapitalization(.sentences)
                            #endif
                            .accessibilityIdentifier("addSubscription.title")
                            .focused($focusedField, equals: .title)
                    }
                    field(.amount) {
                        // Klavye yerel ondalık ayracını gösterir; metin view model'de Decimal'e çevrilir.
                        // Dikey eksen: büyük yazı boyutlarında metin kırpılmaz, sarılır.
                        TextField(
                            String(localized: "Amount", bundle: .module),
                            text: $model.amountText, prompt: Text("Amount (₺)", bundle: .module), axis: .vertical
                        )
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .accessibilityHint(Text("In Turkish lira", bundle: .module))
                            .accessibilityIdentifier("addSubscription.amount")
                            .focused($focusedField, equals: .amount)
                    }
                    field(.card) {
                        // Kart isteğe bağlı; "No card" da bir seçenek.
                        ChoiceRow(title: String(localized: "Card", bundle: .module), value: cardTitle) { choice = .card }
                            .accessibilityIdentifier("addSubscription.card")
                    }
                    field(.period) {
                        ChoiceRow(title: String(localized: "Repeats", bundle: .module), value: AddSubscriptionViewModel.title(of: model.period)) {
                            choice = .period
                        }
                        .accessibilityIdentifier("addSubscription.period")
                    }
                    field(.renewalDay) {
                        Stepper(value: $model.renewalDay, in: Subscription.supportedRenewalDays) {
                            Text("Renews on day \(model.renewalDay)", bundle: .module)
                                .foregroundStyle(Color.vademTextPrimary)
                        }
                        .accessibilityIdentifier("addSubscription.renewalDay")
                    }
                    field(.firstMonth) {
                        ChoiceRow(title: String(localized: "First charge month", bundle: .module), value: model.title(of: model.firstMonth)) {
                            choice = .firstMonth
                        }
                        .accessibilityIdentifier("addSubscription.firstMonth")
                    }
                }
                if model.isEditing {
                    DeleteSection(
                        title: String(localized: "Delete subscription", bundle: .module), identifierPrefix: Self.identifierPrefix,
                        isConfirming: $isConfirmingDelete
                    )
                }
            }
            .deleteConfirmation(
                isPresented: $isConfirmingDelete,
                title: String(localized: "Delete this subscription?", bundle: .module),
                message: String(localized: "All of its charges are removed. This cannot be undone.", bundle: .module),
                identifierPrefix: Self.identifierPrefix
            ) {
                if model.delete() {
                    onDeleted()
                    dismiss()
                }
            }
            .foregroundStyle(Color.vademTextPrimary)
            .tint(Color.vademBrand)
            .navigationDestination(item: $choice) { choice in
                switch choice {
                case .card:
                    OptionList(
                        title: String(localized: "Card", bundle: .module), identifierPrefix: Self.identifierPrefix,
                        options: cardOptions, selection: $model.cardID
                    )
                case .period:
                    OptionList(
                        title: String(localized: "Repeats", bundle: .module), identifierPrefix: Self.identifierPrefix,
                        options: periodOptions, selection: $model.period
                    )
                case .firstMonth:
                    OptionList(
                        title: String(localized: "First charge month", bundle: .module), identifierPrefix: Self.identifierPrefix,
                        options: monthOptions, selection: $model.firstMonth
                    )
                }
            }
            .navigationTitle(
                model.isEditing
                    ? String(localized: "Edit subscription", bundle: .module)
                    : String(localized: "New subscription", bundle: .module)
            )
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            // Taksit formu gibi: çubuk ekranın renk şemasına ve arka planına sabitlenir.
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .toolbarBackground(Color(Color.vademBackground.resolve(in: environment)), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                        .accessibilityIdentifier("addSubscription.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save", bundle: .module)) {
                        if model.save() {
                            onSaved()
                            dismiss()
                        }
                    }
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("addSubscription.save")
                }
            }
        }
    }

    // Seçim listesiyle açılan alanlar.
    private enum Choice: Hashable {
        case card
        case period
        case firstMonth
    }

    private static let identifierPrefix = "addSubscription"
    private static var noCardTitle: String { String(localized: "No card", bundle: .module) }

    private var cardTitle: String {
        model.cards.first { $0.id == model.cardID }?.name ?? Self.noCardTitle
    }

    private var cardOptions: [OptionList<Card.ID?>.Option] {
        [.init(value: nil, title: Self.noCardTitle)]
            + model.cards.map { .init(value: $0.id, title: $0.name) }
    }

    private var periodOptions: [OptionList<Subscription.Period>.Option] {
        AddSubscriptionViewModel.periods.map { .init(value: $0, title: AddSubscriptionViewModel.title(of: $0)) }
    }

    private var monthOptions: [OptionList<YearMonth>.Option] {
        model.firstMonthOptions.map { .init(value: $0, title: model.title(of: $0)) }
    }

    // Alan ve (varsa) altındaki hata metni aynı satırda, alt alta durur.
    private func field(_ field: SubscriptionDraft.Field, @ViewBuilder content: () -> some View) -> some View {
        FormField(
            errorMessage: model.errorMessage(for: field),
            errorIdentifier: "\(Self.identifierPrefix).\(Self.identifier(of: field)).error",
            onTapRow: Self.textFields.contains(field) ? { focusedField = field } : nil,
            content: content
        )
    }

    // Metin alanı olan alanlar; bunların satırına dokunmak alanı odaklar.
    private static let textFields: Set<SubscriptionDraft.Field> = [.title, .amount]

    private static func identifier(of field: SubscriptionDraft.Field) -> String {
        switch field {
        case .title: return "title"
        case .card: return "card"
        case .amount: return "amount"
        case .period: return "period"
        case .renewalDay: return "renewalDay"
        case .firstMonth: return "firstMonth"
        }
    }
}

#if DEBUG
#Preview("Empty") {
    AddSubscriptionView(model: HomeSampleData.makeViewModel().makeAddSubscriptionModel())
}

#Preview("Errors") {
    let model = HomeSampleData.makeViewModel().makeAddSubscriptionModel()
    model.showAllErrors()
    return AddSubscriptionView(model: model)
}
#endif
