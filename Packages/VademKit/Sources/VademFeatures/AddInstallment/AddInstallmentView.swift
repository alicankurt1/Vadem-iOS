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
    @State private var choice: Choice?
    // Kart listesinden açılan kart formunun modeli; nil iken sayfa kapalı.
    @State private var addCardModel: AddCardViewModel?
    private let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                    // Satır bizim çizdiğimiz bir düğme; seçim itilen listede (OptionList) yapılır.
                    // Hazır menü ve gezinme bağlantısı oku denetimde "Dynamic Type desteklenmiyor" sayılıyordu.
                    choiceRow(title: "Card", value: cardTitle, opens: .card)
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
                    choiceRow(title: "First due month", value: model.title(of: model.firstMonth), opens: .firstMonth)
                        .accessibilityIdentifier("addInstallment.firstMonth")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.vademBackground.ignoresSafeArea())
            .foregroundStyle(Color.vademTextPrimary)
            .tint(Color.vademBrand)
            .navigationDestination(item: $choice) { choice in
                switch choice {
                case .card:
                    OptionList(title: "Card", options: cardOptions, selection: $model.cardID) {
                        addCardModel = model.makeAddCardModel()
                    }
                case .firstMonth:
                    OptionList(title: "First due month", options: monthOptions, selection: $model.firstMonth)
                }
            }
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

    // Başlık ve değer normal boyutlarda yan yana, erişilebilirlik boyutlarında alt alta durur.
    // ViewThatFits yerine AnyLayout: metinlerin kimliği boyut değişince korunur; aksi halde
    // denetim yeni oluşan metni "Dynamic Type kısmen desteklenmiyor" sayıyor.
    private func choiceLabel(title: String, value: String) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Text(title)
                .foregroundStyle(Color.vademTextPrimary)
                .frame(maxWidth: stacked ? .infinity : nil, alignment: .leading)
            if !stacked {
                Spacer(minLength: 8)
            }
            Text(value)
                .foregroundStyle(Color.vademTextSecondary)
                .frame(maxWidth: stacked ? .infinity : nil, alignment: .leading)
        }
        .multilineTextAlignment(.leading)
        .contentShape(Rectangle())
    }

    // Dokununca seçim listesini iten satır; ok simgesi metin stiliyle Dynamic Type'a göre büyür.
    private func choiceRow(title: String, value: String, opens choice: Choice) -> some View {
        Button {
            self.choice = choice
        } label: {
            HStack(spacing: 8) {
                choiceLabel(title: title, value: value)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.vademTextSecondary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens a list")
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

/// Seçenekleri tek sütunlu bir listede gösterir; seçilen satır işaretlenir, dokununca geri dönülür.
/// Satırlar düz metin olduğundan Dynamic Type ile büyür ve satır sınırı olmadan sarılır.
/// `onAdd` verilirse listenin sonunda "Add a card" satırı çıkar (yalnızca kart listesinde).
/// Kimlikler: liste `addInstallment.options`, satırlar `addInstallment.option.<sıra>` (0'dan başlar),
/// ekleme satırı `addInstallment.addCard`.
@MainActor
private struct OptionList<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
    }

    let title: String
    let options: [Option]
    @Binding var selection: Value
    var onAdd: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // Satır kimliği değerdir (benzersiz); sıra yalnızca erişilebilirlik kimliği için kullanılır.
            ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
                Button {
                    selection = option.value
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Text(option.title)
                            .foregroundStyle(Color.vademTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if option.value == selection {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.vademBrand)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(option.value == selection ? .isSelected : [])
                .accessibilityIdentifier("addInstallment.option.\(index)")
                .listRowBackground(Color.vademSurface)
            }
            if let onAdd {
                Section {
                    // Seçenek satırları gibi düz metin + gizli simge: Label'ın sabit simge sütunu
                    // denetimde metni "kırpılmış" gösteriyordu; düz metin Dynamic Type ile sarılır.
                    Button(action: onAdd) {
                        HStack(spacing: 8) {
                            Text("Add a card")
                                .foregroundStyle(Color.vademTextPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "plus")
                                .foregroundStyle(Color.vademBrand)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("addInstallment.addCard")
                    .listRowBackground(Color.vademSurface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.vademBackground.ignoresSafeArea())
        .accessibilityIdentifier("addInstallment.options")
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
