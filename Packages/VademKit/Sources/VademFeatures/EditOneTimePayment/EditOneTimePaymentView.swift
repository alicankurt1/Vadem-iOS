import SwiftUI
import VademCore

/// The edit form of a saved one-time payment, shown as a sheet from Home: title, amount, optional card,
/// due month and due day, and a Delete button.
///
/// Each invalid field shows its error below it (once touched); Save stays disabled while the form is
/// invalid. Delete asks for confirmation first. No continuous animations, so it is idle under `-ui-static-motion`.
/// Identifiers: `editOneTime.<field>` for fields (`title`, `amount`, `card`, `dueMonth`, `dueDay`;
/// `dueDay` is a ``DayPickerRow`` with sheet `editOneTime.dueDay.sheet`, `.picker`, `.done`),
/// `editOneTime.<title|amount|card|dueDate>.error` for errors, `editOneTime.save`, `editOneTime.cancel`,
/// `editOneTime.failure`, `editOneTime.delete`, `editOneTime.delete.confirm`, `editOneTime.delete.cancel`;
/// pushed lists use `editOneTime.options` and `editOneTime.option.<index>`.
@MainActor
public struct EditOneTimePaymentView: View {
    /// The launch argument that opens Home with the first saved one-time payment in this form (UI check).
    public nonisolated static let editLaunchArgument = "-ui-edit-onetime"

    @State private var model: EditOneTimePaymentViewModel
    // Silme onayı açık mı.
    @State private var isConfirmingDelete = false
    // Odaktaki metin alanı; satırın boş yerine dokununca o satırın alanı odaklanır.
    @FocusState private var focusedField: OneTimePaymentDraft.Field?
    @State private var choice: Choice?
    private let onSaved: () -> Void
    private let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    /// Creates the form for `model`; `onSaved` runs after a successful save and `onDeleted`
    /// after a successful delete, before the sheet closes.
    public init(
        model: EditOneTimePaymentViewModel, onSaved: @escaping () -> Void = {}, onDeleted: @escaping () -> Void = {}
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
                            .accessibilityIdentifier("\(Self.identifierPrefix).failure")
                    }
                }
                // Tüm alanlar tek kartta, ince çizgilerle ayrılmış satırlar olarak durur.
                FormCard {
                    field(.title) {
                        // Dikey eksen: büyük yazı boyutları kırpılmaz, sarılır.
                        TextField(
                            String(localized: "Title", bundle: .module),
                            text: $model.title, prompt: Text("e.g. Dentist", bundle: .module), axis: .vertical
                        )
                            #if os(iOS)
                            .textInputAutocapitalization(.sentences)
                            #endif
                            .accessibilityIdentifier("\(Self.identifierPrefix).title")
                            .focused($focusedField, equals: .title)
                    }
                    field(.amount) {
                        // Klavye yerel ondalık ayracını gösterir; metin view model'de Decimal'e çevrilir.
                        TextField(
                            String(localized: "Amount", bundle: .module),
                            text: $model.amountText, prompt: Text("Amount (₺)", bundle: .module), axis: .vertical
                        )
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .accessibilityHint(Text("In Turkish lira", bundle: .module))
                            .accessibilityIdentifier("\(Self.identifierPrefix).amount")
                            .focused($focusedField, equals: .amount)
                    }
                    field(.card) {
                        // Kart isteğe bağlı; "No card" da bir seçenek.
                        ChoiceRow(title: String(localized: "Card", bundle: .module), value: cardTitle) { choice = .card }
                            .accessibilityIdentifier("\(Self.identifierPrefix).card")
                    }
                    field(.dueDate) {
                        VStack(alignment: .leading, spacing: 0) {
                            ChoiceRow(title: String(localized: "Due month", bundle: .module), value: model.title(of: model.dueMonth)) {
                                choice = .dueMonth
                            }
                            .accessibilityIdentifier("\(Self.identifierPrefix).dueMonth")
                            DayPickerRow(
                                title: String(localized: "Due day", bundle: .module), day: $model.dueDay,
                                range: 1...model.dueMonth.numberOfDays, identifier: "\(Self.identifierPrefix).dueDay"
                            )
                        }
                    }
                }
                DeleteSection(
                    title: String(localized: "Delete payment", bundle: .module), identifierPrefix: Self.identifierPrefix,
                    isConfirming: $isConfirmingDelete
                )
            }
            .deleteConfirmation(
                isPresented: $isConfirmingDelete,
                title: String(localized: "Delete this payment?", bundle: .module),
                message: String(localized: "This cannot be undone.", bundle: .module),
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
                case .dueMonth:
                    OptionList(
                        title: String(localized: "Due month", bundle: .module), identifierPrefix: Self.identifierPrefix,
                        options: monthOptions, selection: $model.dueMonth
                    )
                }
            }
            .formNavigationTitle(String(localized: "Edit payment", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            // Diğer formlar gibi: çubuk ekranın renk şemasına ve arka planına sabitlenir.
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .toolbarBackground(Color(Color.vademBackground.resolve(in: environment)), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                        .accessibilityIdentifier("\(Self.identifierPrefix).cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if model.save() {
                            onSaved()
                            dismiss()
                        }
                    } label: { Text("Save", bundle: .module) }
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("\(Self.identifierPrefix).save")
                }
            }
        }
    }

    // Seçim listesiyle açılan alanlar.
    private enum Choice: Hashable {
        case card
        case dueMonth
    }

    private static let identifierPrefix = "editOneTime"
    private static var noCardTitle: String { String(localized: "No card", bundle: .module) }

    private var cardTitle: String {
        model.cards.first { $0.id == model.cardID }?.name ?? Self.noCardTitle
    }

    private var cardOptions: [OptionList<Card.ID?>.Option] {
        [.init(value: nil, title: Self.noCardTitle)]
            + model.cards.map { .init(value: $0.id, title: $0.name) }
    }

    private var monthOptions: [OptionList<YearMonth>.Option] {
        model.monthOptions.map { .init(value: $0, title: model.title(of: $0)) }
    }

    // Alan ve (varsa) altındaki hata metni aynı satırda, alt alta durur.
    private func field(_ field: OneTimePaymentDraft.Field, @ViewBuilder content: () -> some View) -> some View {
        FormField(
            errorMessage: model.errorMessage(for: field),
            errorIdentifier: "\(Self.identifierPrefix).\(Self.identifier(of: field)).error",
            onTapRow: Self.textFields.contains(field) ? { focusedField = field } : nil,
            content: content
        )
    }

    // Metin alanı olan alanlar; bunların satırına dokunmak alanı odaklar.
    private static let textFields: Set<OneTimePaymentDraft.Field> = [.title, .amount]

    private static func identifier(of field: OneTimePaymentDraft.Field) -> String {
        switch field {
        case .title: return "title"
        case .card: return "card"
        case .amount: return "amount"
        case .dueDate: return "dueDate"
        }
    }
}

#if DEBUG
#Preview {
    let home = HomeSampleData.makeViewModel()
    let model = home.oneTimePaymentIDs().first.flatMap { home.makeEditOneTimeModel(id: $0) }
    return Group {
        if let model {
            EditOneTimePaymentView(model: model)
        }
    }
}
#endif
