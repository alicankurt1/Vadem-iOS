import SwiftUI
import VademCore

/// The add-installment form, shown as a sheet from Home: title, optional card, payment day
/// (only without a card; with a card the card decides the due day), total amount,
/// number of installments and first due month. A card can be added from the card list,
/// but is never required.
///
/// Each invalid field shows its error below it (once touched); Save stays disabled while
/// the form is invalid. No continuous animations, so it is idle under `-ui-static-motion`.
/// Identifiers: `addInstallment.<field>` for fields and `addInstallment.<field>.error` for errors;
/// the payment day is a ``DayPickerRow`` (`addInstallment.paymentDay`, sheet `addInstallment.paymentDay.sheet`,
/// `.picker`, `.done`).
/// In edit mode (``AddInstallmentViewModel/isEditing``) the title is "Edit installment" and a
/// Delete button (`addInstallment.delete`) asks for confirmation (`addInstallment.delete.confirm`,
/// `addInstallment.delete.cancel`) before deleting.
@MainActor
public struct AddInstallmentView: View {
    /// The launch argument that opens Home with this form already presented (UI check).
    public nonisolated static let launchArgument = "-ui-add-form"
    /// The launch argument that, with ``launchArgument``, also shows every field's error.
    public nonisolated static let errorsLaunchArgument = "-ui-add-form-errors"
    /// The launch argument that opens Home with the first installment of the month in this form, in edit mode (UI check).
    public nonisolated static let editLaunchArgument = "-ui-edit-installment"

    @State private var model: AddInstallmentViewModel
    // Silme onayı açık mı.
    @State private var isConfirmingDelete = false
    // Odaktaki metin alanı; satırın boş yerine dokununca o satırın alanı odaklanır.
    @FocusState private var focusedField: InstallmentDraft.Field?
    @State private var choice: Choice?
    // Kart listesinden açılan kart formunun modeli; nil iken sayfa kapalı.
    @State private var addCardModel: AddCardViewModel?
    private let onSaved: () -> Void
    private let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    /// Creates the form for `model`; `onSaved` runs after a successful save and `onDeleted`
    /// after a successful delete, before the sheet closes.
    public init(
        model: AddInstallmentViewModel, onSaved: @escaping () -> Void = {}, onDeleted: @escaping () -> Void = {}
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
                            .accessibilityIdentifier("addInstallment.failure")
                    }
                }
                // Tüm alanlar tek kartta, ince çizgilerle ayrılmış satırlar olarak durur.
                FormCard {
                    field(.title) {
                        // Dikey eksen: uzun yer tutucu (ör. Türkçe) ve büyük yazı boyutları kırpılmaz, sarılır.
                        TextField(
                            String(localized: "Title", bundle: .module),
                            text: $model.title, prompt: Text("e.g. Laptop", bundle: .module), axis: .vertical
                        )
                            #if os(iOS)
                            .textInputAutocapitalization(.sentences)
                            #endif
                            .accessibilityIdentifier("addInstallment.title")
                            .focused($focusedField, equals: .title)
                    }
                    field(.card) {
                        // Satır bizim çizdiğimiz bir düğme (ChoiceRow); seçim itilen listede (OptionList) yapılır.
                        ChoiceRow(title: String(localized: "Card", bundle: .module), value: cardTitle) { choice = .card }
                            .accessibilityIdentifier("addInstallment.card")
                    }
                    if model.cardID == nil {
                        // Kartsız taksitte vade günü kullanıcıdan gelir; kartlıda karttan.
                        field(.paymentDay) {
                            DayPickerRow(
                                title: String(localized: "Payment day", bundle: .module), day: $model.paymentDay,
                                range: InstallmentItem.supportedPaymentDays, identifier: "addInstallment.paymentDay"
                            )
                        }
                    }
                    field(.amount) {
                        // Klavye yerel ondalık ayracını gösterir; metin view model'de Decimal'e çevrilir.
                        // Dikey eksen: büyük yazı boyutlarında metin kırpılmaz, sarılır; kısa yer tutucu AX5'te de sığar.
                        TextField(
                            String(localized: "Total amount", bundle: .module),
                            text: $model.amountText, prompt: Text("Amount (₺)", bundle: .module), axis: .vertical
                        )
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .accessibilityHint(Text("In Turkish lira", bundle: .module))
                            .accessibilityIdentifier("addInstallment.amount")
                            .focused($focusedField, equals: .amount)
                    }
                    field(.count) {
                        Stepper(value: $model.count, in: InstallmentPlan.supportedCounts) {
                            Text("Installments: \(model.count)", bundle: .module)
                                .foregroundStyle(Color.vademTextPrimary)
                        }
                        .accessibilityIdentifier("addInstallment.count")
                    }
                    field(.firstMonth) {
                        ChoiceRow(title: String(localized: "First due month", bundle: .module), value: model.title(of: model.firstMonth)) { choice = .firstMonth }
                            .accessibilityIdentifier("addInstallment.firstMonth")
                    }
                }
                if model.isEditing {
                    DeleteSection(
                        title: String(localized: "Delete installment", bundle: .module), identifierPrefix: Self.identifierPrefix,
                        isConfirming: $isConfirmingDelete
                    )
                }
            }
            .deleteConfirmation(
                isPresented: $isConfirmingDelete,
                title: String(localized: "Delete this installment?", bundle: .module),
                message: String(localized: "All of its payments are removed. This cannot be undone.", bundle: .module),
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
                    ) {
                        addCardModel = model.makeAddCardModel()
                    }
                case .firstMonth:
                    OptionList(
                        title: String(localized: "First due month", bundle: .module), identifierPrefix: Self.identifierPrefix,
                        options: monthOptions, selection: $model.firstMonth
                    )
                }
            }
            .formNavigationTitle(
                model.isEditing
                    ? String(localized: "Edit installment", bundle: .module)
                    : String(localized: "New installment", bundle: .module)
            )
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            // Galeri gibi: çubuk ekranın renk şemasına ve arka planına sabitlenir.
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .toolbarBackground(Color(Color.vademBackground.resolve(in: environment)), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                        .accessibilityIdentifier("addInstallment.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if model.save() {
                            onSaved()
                            dismiss()
                        }
                    } label: { Text("Save", bundle: .module) }
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("addInstallment.save")
                }
            }
        }
        // Sayfa yığının dışında: kart listesi itilmişken de açılır. Yeni kart kaydedilince
        // kartlar yenilenir, kart seçilir ve forma geri dönülür.
        .sheet(item: $addCardModel) { addCardModel in
            AddCardView(model: addCardModel) { card in
                model.selectAddedCard(card)
                choice = nil
            }
        }
    }

    // Seçim listesiyle açılan alanlar.
    private enum Choice: Hashable {
        case card
        case firstMonth
    }

    private static let identifierPrefix = "addInstallment"
    private static var noCardTitle: String { String(localized: "No card", bundle: .module) }

    private var cardTitle: String {
        model.cards.first { $0.id == model.cardID }?.name ?? Self.noCardTitle
    }

    private var cardOptions: [OptionList<Card.ID?>.Option] {
        [.init(value: nil, title: Self.noCardTitle)]
            + model.cards.map { .init(value: $0.id, title: $0.name) }
    }

    private var monthOptions: [OptionList<YearMonth>.Option] {
        model.firstMonthOptions.map { .init(value: $0, title: model.title(of: $0)) }
    }

    // Alan ve (varsa) altındaki hata metni aynı satırda, alt alta durur.
    private func field(_ field: InstallmentDraft.Field, @ViewBuilder content: () -> some View) -> some View {
        FormField(
            errorMessage: model.errorMessage(for: field),
            errorIdentifier: "\(Self.identifierPrefix).\(Self.identifier(of: field)).error",
            onTapRow: Self.textFields.contains(field) ? { focusedField = field } : nil,
            content: content
        )
    }

    // Metin alanı olan alanlar; bunların satırına dokunmak alanı odaklar.
    private static let textFields: Set<InstallmentDraft.Field> = [.title, .amount]

    private static func identifier(of field: InstallmentDraft.Field) -> String {
        switch field {
        case .title: return "title"
        case .card: return "card"
        case .paymentDay: return "paymentDay"
        case .amount: return "amount"
        case .count: return "count"
        case .firstMonth: return "firstMonth"
        }
    }
}

#if DEBUG
#Preview("Empty") {
    AddInstallmentView(model: HomeSampleData.makeViewModel().makeAddInstallmentModel())
}

#Preview("Errors") {
    let model = HomeSampleData.makeViewModel().makeAddInstallmentModel()
    model.showAllErrors()
    return AddInstallmentView(model: model)
}
#endif
