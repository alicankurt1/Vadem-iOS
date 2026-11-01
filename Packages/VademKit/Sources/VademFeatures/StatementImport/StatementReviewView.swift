import SwiftUI
import VademCore

/// The review step of the statement import, inside the ``AddFlowSheet``: the found installments with a
/// checkbox each, one card and the statement month for all of them, and an "Add N installments" button.
///
/// Each row shows the title, `n/total`, the amount, the payments left and the end month; a possible duplicate
/// gets a "Possible duplicate" badge (and starts unselected). Edit opens a sheet with the title, the amount and
/// both installment numbers. Add saves the selected rows (``StatementReviewViewModel/save()``) and calls
/// `onSaved`; Cancel calls `onCancel` and saves nothing; Back returns to the import screen.
/// No continuous animations, so it is idle under `-ui-static-motion`.
/// Identifiers: the static constants below; rows ``rowIdentifier(_:)`` (the checkbox button, selected trait when
/// selected), ``editIdentifier(_:)``, ``duplicateIdentifier(_:)``, ``rowErrorIdentifier(_:)``; the card and month
/// lists `statementReview.options` with rows `statementReview.option.<index>` (the card list starts with "No card").
@MainActor
public struct StatementReviewView: View {
    /// The launch argument that opens the Add sheet on this screen with ``sampleCandidates`` (debug builds, sample data).
    public nonisolated static let launchArgument = "-ui-statement-review"
    /// The back button (returns to the import screen).
    public nonisolated static let backIdentifier = "statementReview.back"
    /// The cancel button (closes the Add sheet, saves nothing).
    public nonisolated static let cancelIdentifier = "statementReview.cancel"
    /// The screen title.
    public nonisolated static let titleIdentifier = "statementReview.title"
    /// The card row (opens the card list).
    public nonisolated static let cardIdentifier = "statementReview.card"
    /// The statement month row (opens the month list).
    public nonisolated static let statementMonthIdentifier = "statementReview.statementMonth"
    /// The "Add N installments" button.
    public nonisolated static let saveIdentifier = "statementReview.save"
    /// The load or save failure message.
    public nonisolated static let failureIdentifier = "statementReview.failure"
    /// The list of rows.
    public nonisolated static let rowsIdentifier = "statementReview.rows"
    /// The edit sheet's title field.
    public nonisolated static let editTitleIdentifier = "statementReview.edit.title"
    /// The edit sheet's amount field.
    public nonisolated static let editAmountIdentifier = "statementReview.edit.amount"
    /// The edit sheet's current installment stepper.
    public nonisolated static let editCurrentIdentifier = "statementReview.edit.current"
    /// The edit sheet's installment count stepper.
    public nonisolated static let editTotalIdentifier = "statementReview.edit.total"
    /// The edit sheet's error message.
    public nonisolated static let editErrorIdentifier = "statementReview.edit.error"
    /// The edit sheet's Done button.
    public nonisolated static let editDoneIdentifier = "statementReview.edit.done"

    /// The checkbox button of the row at `index` (0-based, statement order).
    public nonisolated static func rowIdentifier(_ index: Int) -> String { "statementReview.row.\(index)" }
    /// The edit button of the row at `index`.
    public nonisolated static func editIdentifier(_ index: Int) -> String { "statementReview.row.\(index).edit" }
    /// The "Possible duplicate" badge of the row at `index`.
    public nonisolated static func duplicateIdentifier(_ index: Int) -> String { "statementReview.row.\(index).duplicate" }
    /// The error message of the row at `index`.
    public nonisolated static func rowErrorIdentifier(_ index: Int) -> String { "statementReview.row.\(index).error" }

    @Bindable private var model: StatementReviewViewModel
    private let onBack: () -> Void
    private let onCancel: () -> Void
    private let onSaved: () -> Void

    @State private var choice: Choice?
    @State private var editing: EditTarget?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates the screen for `model`; `onBack` returns to the import screen, `onCancel` closes without saving,
    /// `onSaved` runs after a successful save.
    public init(
        model: StatementReviewViewModel,
        onBack: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onSaved: @escaping () -> Void
    ) {
        self.model = model
        self.onBack = onBack
        self.onCancel = onCancel
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Review installments", bundle: .module)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.vademTextPrimary)
                            // Metin her boyutta tam yüksekliğini alır, sarılır; asla kırpılmaz.
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier(Self.titleIdentifier)
                        Text("Check what was found. Only the selected installments are added.", bundle: .module)
                            .font(.subheadline)
                            .foregroundStyle(Color.vademTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let message = model.failureMessage {
                            FormCard {
                                FormFailureRow(message: message)
                                    .accessibilityIdentifier(Self.failureIdentifier)
                            }
                        }
                        FormCard {
                            ChoiceRow(title: String(localized: "Card", bundle: .module), value: model.cardTitle) {
                                choice = .card
                            }
                            .accessibilityIdentifier(Self.cardIdentifier)
                            ChoiceRow(
                                title: String(localized: "Statement month", bundle: .module),
                                value: model.title(of: model.statementMonth)
                            ) {
                                choice = .statementMonth
                            }
                            .accessibilityIdentifier(Self.statementMonthIdentifier)
                        }
                        rowList
                    }
                    // 20 pt yan boşluk: sol kenarda her zaman arka plan rengi kalır.
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                saveButton
            }
            .background(Color.vademBackground.ignoresSafeArea())
            #if os(iOS)
            // Kök ekranın kendi başlığı var; çubuk yalnızca itilen listelerde görünür.
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .navigationDestination(item: $choice) { choice in
                switch choice {
                case .card:
                    OptionList(
                        title: String(localized: "Card", bundle: .module), identifierPrefix: Self.identifierPrefix,
                        options: cardOptions, selection: $model.cardID
                    )
                case .statementMonth:
                    OptionList(
                        title: String(localized: "Statement month", bundle: .module), identifierPrefix: Self.identifierPrefix,
                        options: monthOptions, selection: $model.statementMonth
                    )
                }
            }
        }
        .tint(Color.vademBrand)
        .sheet(item: $editing) { target in
            StatementReviewRowEditor(model: model, index: target.index)
        }
    }

    // Geri solda, vazgeç sağda; ikisi de en az 44 pt dokunma alanında.
    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.vademTextPrimary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Back", bundle: .module))
            .accessibilityIdentifier(Self.backIdentifier)
            Spacer(minLength: 0)
            Button(action: onCancel) {
                Text("Cancel", bundle: .module)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.vademBrand)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(Self.cancelIdentifier)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .frame(minHeight: 52)
    }

    private var rowList: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider().overlay(Color.vademSeparator)
                }
                rowView(row, at: index)
            }
        }
        .background(Color.vademSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.rowsIdentifier)
    }

    // Onay kutusu satırın tamamı (tek düğme); düzenle düğmesi yanda, AX5'te altta. Tekrar rozeti ve hata ayrı öğeler.
    private func rowView(_ row: StatementReviewRow, at index: Int) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        return VStack(alignment: .leading, spacing: 8) {
            layout {
                checkboxButton(row, at: index)
                editButton(row, at: index)
            }
            if model.isPossibleDuplicate(row) {
                DueChip(String(localized: "Possible duplicate", bundle: .module), kind: .soon)
                    .accessibilityIdentifier(Self.duplicateIdentifier(index))
            }
            if let message = model.errorMessage(for: row) {
                FieldErrorLabel(message: message)
                    .accessibilityIdentifier(Self.rowErrorIdentifier(index))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func checkboxButton(_ row: StatementReviewRow, at index: Int) -> some View {
        let amount = model.candidate(for: row).map { Money($0.installmentAmount) }
        return Button {
            model.toggleSelection(at: index)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: row.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(row.isSelected ? Color.vademBrand : Color.vademTextSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle(row))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.vademTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "\(row.currentInstallment)/\(row.totalInstallments)")
                            .monospacedDigit()
                        if let amount {
                            AmountText(amount)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.vademTextSecondary)
                    if let remaining = remainingText(row) {
                        Text(remaining)
                            .font(.subheadline)
                            .foregroundStyle(Color.vademTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Tek öğe, tam etiketle: başlık, taksit sırası, tutar ve kalanlar; seçim durumu özellik olarak.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(row, amount: amount))
        .accessibilityAddTraits(row.isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(Self.rowIdentifier(index))
    }

    private func editButton(_ row: StatementReviewRow, at index: Int) -> some View {
        Button {
            editing = EditTarget(index: index)
        } label: {
            Image(systemName: "pencil")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.vademBrand)
                // En az 44 pt dokunma alanı.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Edit \(displayTitle(row))", bundle: .module))
        .accessibilityIdentifier(Self.editIdentifier(index))
    }

    private var saveButton: some View {
        Button {
            if model.save() { onSaved() }
        } label: {
            Text(model.saveTitle)
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
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibilityIdentifier(Self.saveIdentifier)
    }

    private func displayTitle(_ row: StatementReviewRow) -> String {
        let trimmed = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "No title", bundle: .module) : trimmed
    }

    // "Kalan: 4 · Bitiş: Ocak 2027"; taksit numaraları geçersizse gösterilmez.
    private func remainingText(_ row: StatementReviewRow) -> String? {
        guard let end = model.endMonth(of: row) else { return nil }
        return String(
            localized: "Remaining: \(model.remainingInstallments(of: row)) · Ends \(model.title(of: end))",
            bundle: .module
        )
    }

    private func accessibilityLabel(_ row: StatementReviewRow, amount: Money?) -> Text {
        var label = Text(displayTitle(row)) + Text(verbatim: ", ")
            + Text("installment \(row.currentInstallment) of \(row.totalInstallments)", bundle: .module)
        if let amount {
            label = label + Text(verbatim: ", ") + Text(AmountText.spokenLabel(amount))
        }
        if let remaining = remainingText(row) {
            label = label + Text(verbatim: ", ") + Text(remaining)
        }
        return label
    }

    private var cardOptions: [OptionList<Card.ID?>.Option] {
        [.init(value: nil, title: String(localized: "No card", bundle: .module))]
            + model.cards.map { .init(value: $0.id, title: $0.name) }
    }

    private var monthOptions: [OptionList<YearMonth>.Option] {
        model.statementMonthOptions.map { .init(value: $0, title: model.title(of: $0)) }
    }

    // Seçim listesiyle açılan alanlar.
    private enum Choice: Hashable {
        case card
        case statementMonth
    }

    // Düzenlenen satırın sırası; sayfa bununla açılır.
    private struct EditTarget: Identifiable {
        let index: Int
        var id: Int { index }
    }

    private static let identifierPrefix = "statementReview"
}

/// The edit sheet of one review row: title, per-installment amount, current installment and count.
/// Changes apply to the row at once; Done closes the sheet.
@MainActor
private struct StatementReviewRowEditor: View {
    @Bindable var model: StatementReviewViewModel
    let index: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    var body: some View {
        NavigationStack {
            FormScroll {
                if model.rows.indices.contains(index) {
                    let row = model.rows[index]
                    FormCard {
                        FormField(title: String(localized: "Title", bundle: .module)) {
                            // Dikey eksen: büyük yazı boyutlarında metin kırpılmaz, sarılır.
                            TextField(
                                String(localized: "Title", bundle: .module),
                                text: $model.rows[index].title, axis: .vertical
                            )
                            .accessibilityIdentifier(StatementReviewView.editTitleIdentifier)
                        }
                        FormField(title: String(localized: "Amount per installment", bundle: .module)) {
                            TextField(
                                String(localized: "Amount per installment", bundle: .module),
                                text: $model.rows[index].amountText, axis: .vertical
                            )
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .accessibilityHint(Text("In Turkish lira", bundle: .module))
                            .accessibilityIdentifier(StatementReviewView.editAmountIdentifier)
                        }
                        FormField {
                            Stepper(
                                value: Binding(
                                    get: { model.rows[index].currentInstallment },
                                    set: { model.setCurrentInstallment($0, at: index) }
                                ),
                                in: 1...max(row.totalInstallments, 1)
                            ) {
                                Text("Current installment: \(row.currentInstallment)", bundle: .module)
                                    .foregroundStyle(Color.vademTextPrimary)
                            }
                            .accessibilityIdentifier(StatementReviewView.editCurrentIdentifier)
                        }
                        FormField {
                            Stepper(
                                value: Binding(
                                    get: { model.rows[index].totalInstallments },
                                    set: { model.setTotalInstallments($0, at: index) }
                                ),
                                in: InstallmentPlan.supportedCounts
                            ) {
                                Text("Installments: \(row.totalInstallments)", bundle: .module)
                                    .foregroundStyle(Color.vademTextPrimary)
                            }
                            .accessibilityIdentifier(StatementReviewView.editTotalIdentifier)
                        }
                    }
                    if let message = model.errorMessage(for: row) {
                        FormCard {
                            FieldErrorLabel(message: message)
                                .padding(.vertical, 8)
                                .accessibilityIdentifier(StatementReviewView.editErrorIdentifier)
                        }
                    }
                }
            }
            .foregroundStyle(Color.vademTextPrimary)
            .tint(Color.vademBrand)
            .formNavigationTitle(String(localized: "Edit installment", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            // Formlar gibi: çubuk ekranın renk şemasına ve arka planına sabitlenir.
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .toolbarBackground(Color(Color.vademBackground.resolve(in: environment)), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                        .accessibilityIdentifier(StatementReviewView.editDoneIdentifier)
                }
            }
        }
    }
}

#if DEBUG
extension StatementReviewView {
    /// Four sample candidates for the debug launch argument; the third ("Laptop", 4,000 TL, 4/12) duplicates the
    /// sample data's Laptop installment (48,000 TL in 12 from July 2026, so 4,000 TL a month) on the Everyday card
    /// (the first card, so the default).
    public static var sampleCandidates: [InstallmentCandidate] {
        [
            InstallmentCandidate(
                id: sampleID(1), merchant: "ORNEK ELEKTRONIK", installmentAmount: Decimal(123_456) / 100,
                currentInstallment: 3, totalInstallments: 6
            ),
            InstallmentCandidate(
                id: sampleID(2), merchant: "ORNEK GIYIM", installmentAmount: Decimal(450),
                currentInstallment: 2, totalInstallments: 4
            ),
            InstallmentCandidate(
                id: sampleID(3), merchant: "LAPTOP", installmentAmount: Decimal(4_000),
                currentInstallment: 4, totalInstallments: 12
            ),
            InstallmentCandidate(
                id: sampleID(4), merchant: "ORNEK MOBILYA", installmentAmount: Decimal(2_500),
                currentInstallment: 5, totalInstallments: 12
            ),
        ]
    }

    // Sabit id'ler: her açılışta aynı satırlar.
    private static func sampleID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000002%02d", number))!
    }
}
#endif
