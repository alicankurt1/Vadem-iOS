import SwiftUI
import VademCore

/// The add-installment form, shown as a sheet from Home: title, card, total amount,
/// number of installments and first due month.
///
/// Each invalid field shows its error below it (once touched); Save stays disabled while
/// the form is invalid. No continuous animations, so it is idle under `-ui-static-motion`.
/// Identifiers: `addInstallment.<field>` for fields and `addInstallment.<field>.error` for errors.
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
            Form {
                if let message = model.failureMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.vademTextPrimary)
                            .accessibilityIdentifier("addInstallment.failure")
                    }
                    .listRowBackground(Color.vademSurface)
                }
                field(.title) {
                    TextField("Title", text: $model.title, prompt: Text("e.g. Laptop"))
                        #if os(iOS)
                        .textInputAutocapitalization(.sentences)
                        #endif
                        .accessibilityIdentifier("addInstallment.title")
                }
                field(.card) {
                    // Satır bizim çizdiğimiz bir düğme (ChoiceRow); seçim itilen listede (OptionList) yapılır.
                    ChoiceRow(title: "Card", value: cardTitle) { choice = .card }
                        .accessibilityIdentifier("addInstallment.card")
                }
                field(.amount) {
                    // Klavye yerel ondalık ayracını gösterir; metin view model'de Decimal'e çevrilir.
                    // Dikey eksen: büyük yazı boyutlarında metin kırpılmaz, sarılır; kısa yer tutucu AX5'te de sığar.
                    TextField("Total amount", text: $model.amountText, prompt: Text("Amount (₺)"), axis: .vertical)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityHint("In Turkish lira")
                        .accessibilityIdentifier("addInstallment.amount")
                }
                field(.count) {
                    Stepper(value: $model.count, in: InstallmentPlan.supportedCounts) {
                        Text("Installments: \(model.count)")
                            .foregroundStyle(Color.vademTextPrimary)
                    }
                    .accessibilityIdentifier("addInstallment.count")
                }
                field(.firstMonth) {
                    ChoiceRow(title: "First due month", value: model.title(of: model.firstMonth)) { choice = .firstMonth }
                        .accessibilityIdentifier("addInstallment.firstMonth")
                }
                if model.isEditing {
                    DeleteSection(
                        title: "Delete installment", identifierPrefix: Self.identifierPrefix,
                        isConfirming: $isConfirmingDelete
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .deleteConfirmation(
                isPresented: $isConfirmingDelete,
                title: "Delete this installment?",
                message: "All of its payments are removed. This cannot be undone.",
                identifierPrefix: Self.identifierPrefix
            ) {
                if model.delete() {
                    onDeleted()
                    dismiss()
                }
            }
            .background(Color.vademBackground.ignoresSafeArea())
            .foregroundStyle(Color.vademTextPrimary)
            .tint(Color.vademBrand)
            .navigationDestination(item: $choice) { choice in
                switch choice {
                case .card:
                    OptionList(
                        title: "Card", identifierPrefix: Self.identifierPrefix,
                        options: cardOptions, selection: $model.cardID
                    ) {
                        addCardModel = model.makeAddCardModel()
                    }
                case .firstMonth:
                    OptionList(
                        title: "First due month", identifierPrefix: Self.identifierPrefix,
                        options: monthOptions, selection: $model.firstMonth
                    )
                }
            }
            .navigationTitle(model.isEditing ? "Edit installment" : "New installment")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            // Galeri gibi: çubuk ekranın renk şemasına ve arka planına sabitlenir.
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .toolbarBackground(Color(Color.vademBackground.resolve(in: environment)), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("addInstallment.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.save() {
                            onSaved()
                            dismiss()
                        }
                    }
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
    private static let noCardTitle = "Choose a card"

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

    // Alan ve (varsa) altındaki hata metni aynı bölümde durur.
    private func field(_ field: InstallmentDraft.Field, @ViewBuilder content: () -> some View) -> some View {
        FormFieldSection(
            errorMessage: model.errorMessage(for: field),
            errorIdentifier: "\(Self.identifierPrefix).\(Self.identifier(of: field)).error",
            content: content
        )
    }

    private static func identifier(of field: InstallmentDraft.Field) -> String {
        switch field {
        case .title: return "title"
        case .card: return "card"
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
