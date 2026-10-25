import SwiftUI
import VademCore

/// The add-card form, shown as a sheet from Home or from the add-installment form's card
/// list: name, statement day and due day.
///
/// Each invalid field shows its error below it (once touched); Save stays disabled while
/// the form is invalid. No continuous animations, so it is idle under `-ui-static-motion`.
/// Identifiers: `addCard.<field>` for fields (`name`, `statementDay`, `dueDay`),
/// `addCard.<field>.error` for errors, `addCard.save`, `addCard.cancel`, `addCard.failure`.
/// In edit mode (``AddCardViewModel/isEditing``) the title is "Edit card" and a Delete button
/// (`addCard.delete`) asks for confirmation (`addCard.delete.confirm`, `addCard.delete.cancel`);
/// a card still in use is not deleted and the reason shows in `addCard.failure`.
@MainActor
public struct AddCardView: View {
    /// The launch argument that opens Home with this form already presented (UI check).
    public nonisolated static let launchArgument = "-ui-add-card-form"
    /// The launch argument that, with ``launchArgument``, also shows every field's error.
    public nonisolated static let errorsLaunchArgument = "-ui-add-card-form-errors"
    /// The launch argument that opens Home with the first card of the month's subtotals in this form,
    /// in edit mode (UI check). In the sample data that card is in use, so deleting it shows the error.
    public nonisolated static let editLaunchArgument = "-ui-edit-card"

    @State private var model: AddCardViewModel
    // Silme onayı açık mı.
    @State private var isConfirmingDelete = false
    // Odaktaki metin alanı; satırın boş yerine dokununca o satırın alanı odaklanır.
    @FocusState private var focusedField: CardDraft.Field?
    private let onSaved: (Card) -> Void
    private let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    /// Creates the form for `model`; `onSaved` gets the stored card after a successful save,
    /// and `onDeleted` runs after a successful delete, before the sheet closes.
    public init(
        model: AddCardViewModel, onSaved: @escaping (Card) -> Void = { _ in }, onDeleted: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: model)
        self.onSaved = onSaved
        self.onDeleted = onDeleted
    }

    public var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                FormScroll {
                    if let message = model.failureMessage {
                        // Kaydırma hedefi kartın kendisi: SurfaceCard'ın satırları yeniden sardığı içerikte
                        // değil, ScrollView'un doğrudan alt görünümünde durur.
                        FormCard {
                            FormFailureRow(message: message)
                                .accessibilityIdentifier("addCard.failure")
                        }
                        .id(Self.failureID)
                    }
                    // Alanlar tek kartta. Alan adı alanın üstünde (sarılabilen düz metin); yer tutucular
                    // AX5'te de sığacak kadar kısa. Dikey eksen: yazılan metin kırpılmaz, sarılır.
                    FormCard {
                        field(.name, title: String(localized: "Card name", bundle: .module)) {
                            TextField(
                                String(localized: "Card name", bundle: .module),
                                text: nameBinding, prompt: Text("e.g. Everyday", bundle: .module), axis: .vertical
                            )
                                #if os(iOS)
                                .textInputAutocapitalization(.words)
                                #endif
                                .accessibilityIdentifier("addCard.name")
                                .focused($focusedField, equals: .name)
                        }
                        field(.statementDay, title: String(localized: "Statement day", bundle: .module)) {
                            TextField(
                                String(localized: "Statement day", bundle: .module),
                                text: $model.statementDayText, prompt: Text("1–31", bundle: .module), axis: .vertical
                            )
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .accessibilityHint(Text("The day of the month the statement is cut", bundle: .module))
                                .accessibilityIdentifier("addCard.statementDay")
                                .focused($focusedField, equals: .statementDay)
                        }
                        field(.dueDay, title: String(localized: "Due day", bundle: .module)) {
                            TextField(
                                String(localized: "Due day", bundle: .module),
                                text: $model.dueDayText, prompt: Text("1–31", bundle: .module), axis: .vertical
                            )
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .accessibilityHint(Text("The day of the month the payment is due", bundle: .module))
                                .accessibilityIdentifier("addCard.dueDay")
                                .focused($focusedField, equals: .dueDay)
                        }
                    }
                    if model.isEditing {
                        // Kullanımdaki kart silinmez; neden formun üstündeki hata satırında gösterilir.
                        DeleteSection(title: String(localized: "Delete card", bundle: .module), identifierPrefix: "addCard", isConfirming: $isConfirmingDelete)
                    }
                }
                .deleteConfirmation(
                    isPresented: $isConfirmingDelete,
                    title: String(localized: "Delete this card?", bundle: .module),
                    message: String(localized: "Cards used by installments or subscriptions cannot be deleted.", bundle: .module),
                    identifierPrefix: "addCard"
                ) {
                    if model.delete() {
                        onDeleted()
                        dismiss()
                    }
                }
                // Silme reddedilince form en alttadır; hata satırı görünsün diye başa kaydırılır.
                .onChange(of: model.failureMessage) { _, message in
                    guard let message else { return }
                    proxy.scrollTo(Self.failureID, anchor: .top)
                    // VoiceOver kullanıcısı da hatayı duyar.
                    AccessibilityNotification.Announcement(message).post()
                }
            }
            .foregroundStyle(Color.vademTextPrimary)
            .tint(Color.vademBrand)
            .navigationTitle(
                model.isEditing
                    ? String(localized: "Edit card", bundle: .module)
                    : String(localized: "New card", bundle: .module)
            )
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            // Ekleme formu gibi: çubuk ekranın renk şemasına ve arka planına sabitlenir.
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .toolbarBackground(Color(Color.vademBackground.resolve(in: environment)), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                        .accessibilityIdentifier("addCard.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if model.save(), let card = model.savedCard {
                            onSaved(card)
                            dismiss()
                        }
                    } label: { Text("Save", bundle: .module) }
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("addCard.save")
                }
            }
        }
    }

    private static let failureID = "addCard.failure"

    // Dikey alanda Return yeni satır ekler; kart adı tek satırlık olduğundan satır sonları atılır.
    private var nameBinding: Binding<String> {
        Binding(
            get: { model.name },
            set: { model.name = $0.replacingOccurrences(of: "\n", with: "") }
        )
    }

    // Alan, başlığı ve (varsa) altındaki hata metni aynı satırda, alt alta durur.
    private func field(_ field: CardDraft.Field, title: String, @ViewBuilder content: () -> some View) -> some View {
        FormField(
            title: title,
            errorMessage: model.errorMessage(for: field),
            errorIdentifier: "addCard.\(Self.identifier(of: field)).error",
            onTapRow: Self.textFields.contains(field) ? { focusedField = field } : nil,
            content: content
        )
    }

    // Metin alanı olan alanlar; bunların satırına dokunmak alanı odaklar.
    private static let textFields: Set<CardDraft.Field> = [.name, .statementDay, .dueDay]

    private static func identifier(of field: CardDraft.Field) -> String {
        switch field {
        case .name: return "name"
        case .statementDay: return "statementDay"
        case .dueDay: return "dueDay"
        }
    }
}

#if DEBUG
#Preview("Empty") {
    AddCardView(model: AddCardViewModel(repository: InMemoryPaymentRepository()))
}

#Preview("Errors") {
    let model = AddCardViewModel(repository: InMemoryPaymentRepository())
    model.showAllErrors()
    return AddCardView(model: model)
}
#endif
