import SwiftUI
import VademCore

/// The add-card form, shown as a sheet from Home or from the add-installment form's card
/// list: name, statement day and due day.
///
/// Each invalid field shows its error below it (once touched); Save stays disabled while
/// the form is invalid. No continuous animations, so it is idle under `-ui-static-motion`.
/// Identifiers: `addCard.<field>` for fields (`name`, `statementDay`, `dueDay`),
/// `addCard.<field>.error` for errors, `addCard.save`, `addCard.cancel`, `addCard.failure`.
@MainActor
public struct AddCardView: View {
    /// The launch argument that opens Home with this form already presented (UI check).
    public nonisolated static let launchArgument = "-ui-add-card-form"
    /// The launch argument that, with ``launchArgument``, also shows every field's error.
    public nonisolated static let errorsLaunchArgument = "-ui-add-card-form-errors"

    @State private var model: AddCardViewModel
    private let onSaved: (Card) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    /// Creates the form for `model`; `onSaved` gets the stored card after a successful save,
    /// before the sheet closes.
    public init(model: AddCardViewModel, onSaved: @escaping (Card) -> Void = { _ in }) {
        _model = State(initialValue: model)
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            Form {
                if let message = model.failureMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.vademTextPrimary)
                            .accessibilityIdentifier("addCard.failure")
                    }
                    .listRowBackground(Color.vademSurface)
                }
                // Alan adı bölüm başlığında (sarılabilen düz metin); yer tutucular AX5'te de
                // sığacak kadar kısa. Dikey eksen: yazılan metin kırpılmaz, sarılır.
                field(.name, title: "Card name") {
                    TextField("Card name", text: nameBinding, prompt: Text("e.g. Everyday"), axis: .vertical)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                        .accessibilityIdentifier("addCard.name")
                }
                field(.statementDay, title: "Statement day") {
                    TextField("Statement day", text: $model.statementDayText, prompt: Text("1–31"), axis: .vertical)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .accessibilityHint("The day of the month the statement is cut")
                        .accessibilityIdentifier("addCard.statementDay")
                }
                field(.dueDay, title: "Due day") {
                    TextField("Due day", text: $model.dueDayText, prompt: Text("1–31"), axis: .vertical)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .accessibilityHint("The day of the month the payment is due")
                        .accessibilityIdentifier("addCard.dueDay")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.vademBackground.ignoresSafeArea())
            .foregroundStyle(Color.vademTextPrimary)
            .tint(Color.vademBrand)
            .navigationTitle("New card")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            // Ekleme formu gibi: çubuk ekranın renk şemasına ve arka planına sabitlenir.
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .toolbarBackground(Color(Color.vademBackground.resolve(in: environment)), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("addCard.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.save(), let card = model.savedCard {
                            onSaved(card)
                            dismiss()
                        }
                    }
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("addCard.save")
                }
            }
        }
    }

    // Dikey alanda Return yeni satır ekler; kart adı tek satırlık olduğundan satır sonları atılır.
    private var nameBinding: Binding<String> {
        Binding(
            get: { model.name },
            set: { model.name = $0.replacingOccurrences(of: "\n", with: "") }
        )
    }

    // Alan, başlığı ve (varsa) altındaki hata metni aynı bölümde durur.
    private func field(_ field: CardDraft.Field, title: String, @ViewBuilder content: () -> some View) -> some View {
        Section {
            content()
            if let message = model.errorMessage(for: field) {
                // Hata yalnızca renkle değil, simge ve metinle de belirtilir.
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.vademTextPrimary)
                    .accessibilityIdentifier("addCard.\(Self.identifier(of: field)).error")
            }
        } header: {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.vademTextSecondary)
                .textCase(nil)
        }
        .listRowBackground(Color.vademSurface)
    }

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
