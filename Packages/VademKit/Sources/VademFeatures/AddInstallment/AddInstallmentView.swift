import SwiftUI
import VademCore

/// The add-installment form, shown as a sheet from Home: title, card, total amount,
/// number of installments and first due month.
///
/// Each invalid field shows its error below it (once touched); Save stays disabled while
/// the form is invalid. No continuous animations, so it is idle under `-ui-static-motion`.
/// Identifiers: `addInstallment.<field>` for fields and `addInstallment.<field>.error` for errors.
@MainActor
public struct AddInstallmentView: View {
    /// The launch argument that opens Home with this form already presented (UI check).
    public nonisolated static let launchArgument = "-ui-add-form"
    /// The launch argument that, with ``launchArgument``, also shows every field's error.
    public nonisolated static let errorsLaunchArgument = "-ui-add-form-errors"

    @State private var model: AddInstallmentViewModel
    private let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    /// Creates the form for `model`; `onSaved` runs after a successful save, before the sheet closes.
    public init(model: AddInstallmentViewModel, onSaved: @escaping () -> Void = {}) {
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
                    Picker("Card", selection: $model.cardID) {
                        Text("Choose a card").tag(Card.ID?.none)
                        ForEach(model.cards) { card in
                            Text(card.name).tag(Card.ID?.some(card.id))
                        }
                    }
                    .accessibilityIdentifier("addInstallment.card")
                }
                field(.amount) {
                    // Klavye yerel ondalık ayracını gösterir; metin view model'de Decimal'e çevrilir.
                    TextField("Total amount", text: $model.amountText, prompt: Text("Total amount (₺)"))
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityLabel("Total amount in Turkish lira")
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
                    Picker("First due month", selection: $model.firstMonth) {
                        ForEach(model.firstMonthOptions, id: \.self) { month in
                            Text(model.title(of: month)).tag(month)
                        }
                    }
                    .accessibilityIdentifier("addInstallment.firstMonth")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.vademBackground.ignoresSafeArea())
            .foregroundStyle(Color.vademTextPrimary)
            .tint(Color.vademBrand)
            .navigationTitle("New installment")
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
    }

    // Alan ve (varsa) altındaki hata metni aynı bölümde durur.
    private func field(_ field: InstallmentDraft.Field, @ViewBuilder content: () -> some View) -> some View {
        Section {
            content()
            if let message = model.errorMessage(for: field) {
                // Hata yalnızca renkle değil, simge ve metinle de belirtilir.
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.vademTextPrimary)
                    .accessibilityIdentifier("addInstallment.\(Self.identifier(of: field)).error")
            }
        }
        .listRowBackground(Color.vademSurface)
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
