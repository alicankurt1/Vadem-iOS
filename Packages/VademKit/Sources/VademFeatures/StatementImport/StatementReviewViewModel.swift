import Foundation
import Observation
import VademCore

/// One found installment on the review screen: whether it will be added and its editable values.
public struct StatementReviewRow: Identifiable, Hashable, Sendable {
    /// The candidate's id.
    public let id: UUID
    /// `true` when Add saves this row.
    public var isSelected: Bool
    /// The title to save; starts at the candidate's ``VademCore/InstallmentCandidate/suggestedTitle``.
    public var title: String
    /// The per-installment amount as typed (the locale's decimal separator, no grouping).
    public var amountText: String
    /// The installment the statement is for, e.g. `3` in `3/6`.
    public var currentInstallment: Int
    /// The number of installments, e.g. `6` in `3/6`.
    public var totalInstallments: Int
}

/// Drives the review step of the statement import: the user confirms, edits or unselects the found
/// installments, picks one card and the statement month, and adds the selected ones in one go.
///
/// Rows start selected, except possible duplicates of saved installments
/// (``VademCore/InstallmentCandidate/isPossibleDuplicate(of:cardID:)`` with the card chosen at start).
/// The card starts at the last used card, else the first card (``LastUsedCardStore``); without cards the
/// installments are card-less, paid on today's day. The statement month starts at today's month; each plan
/// is built so its current installment falls in that month. Nothing is saved before ``save()``.
/// "Today" is injected (`todayMonth`, `todayDay`), never read from the clock.
@MainActor
@Observable
public final class StatementReviewViewModel: Identifiable {
    /// Months offered before today's month in the statement month list.
    public nonisolated static let monthsBefore = 12
    /// Months offered after today's month in the statement month list.
    public nonisolated static let monthsAfter = 1

    /// The rows, in statement order.
    public var rows: [StatementReviewRow]
    /// The cards to choose from, in the repository's order.
    public private(set) var cards: [Card] = []
    /// The card for every added installment, or `nil` for card-less installments.
    public var cardID: Card.ID?
    /// The month of the statement: the current installment of every row falls in it.
    public var statementMonth: YearMonth
    /// The months the statement month list offers, in order; contains today's month.
    public let statementMonthOptions: [YearMonth]
    /// A message for a load or save failure, or `nil`.
    public private(set) var failureMessage: String?

    @ObservationIgnored private let repository: any PaymentRepository
    @ObservationIgnored private let lastUsedCard: LastUsedCardStore
    @ObservationIgnored private let todayDay: Int
    @ObservationIgnored private let locale: Locale
    // Kayıtlı taksitler bir kez okunur; olası tekrar kontrolü bunlarla yapılır.
    @ObservationIgnored private var existing: [InstallmentItem] = []

    /// Creates the review for `candidates` and loads the cards and saved installments.
    ///
    /// `todayMonth` is the default statement month, `todayDay` the payment day of card-less installments;
    /// `locale` decides the amount text's decimal separator.
    public init(
        candidates: [InstallmentCandidate],
        repository: any PaymentRepository,
        todayMonth: YearMonth,
        todayDay: Int,
        lastUsedCard: LastUsedCardStore,
        locale: Locale = .current
    ) {
        self.repository = repository
        self.lastUsedCard = lastUsedCard
        self.todayDay = min(max(todayDay, InstallmentItem.supportedPaymentDays.lowerBound), InstallmentItem.supportedPaymentDays.upperBound)
        self.locale = locale
        self.statementMonth = todayMonth
        self.statementMonthOptions = MonthOptions.months(
            around: todayMonth, before: Self.monthsBefore, after: Self.monthsAfter
        )
        self.rows = []
        do {
            cards = try repository.cards()
            existing = try repository.installments()
        } catch {
            failureMessage = AddInstallmentViewModel.cardsLoadErrorMessage
        }
        cardID = CardPicker.initialSelection(cards: cards, lastUsedCardID: lastUsedCard.cardID) ?? cards.first?.id
        rows = candidates.map { candidate in
            let isDuplicate = candidate.isPossibleDuplicate(of: existing, cardID: cardID)
            return StatementReviewRow(
                id: candidate.id,
                isSelected: !isDuplicate,
                title: candidate.suggestedTitle,
                amountText: AmountInput.text(for: Money(candidate.installmentAmount).amount, locale: locale),
                currentInstallment: candidate.currentInstallment,
                totalInstallments: candidate.totalInstallments
            )
        }
    }

    // MARK: Satırlar

    /// The number of selected rows.
    public var selectedCount: Int {
        rows.count { $0.isSelected }
    }

    /// The Add button's title: "Add N installments" with N = ``selectedCount``.
    public var saveTitle: String {
        String(localized: "Add \(selectedCount) installments", bundle: .module)
    }

    /// Selects or unselects the row at `index`.
    public func toggleSelection(at index: Int) {
        guard rows.indices.contains(index) else { return }
        rows[index].isSelected.toggle()
    }

    /// Sets the number of installments of the row at `index`, clamped to ``VademCore/InstallmentPlan/supportedCounts``;
    /// the current installment is lowered to it when needed.
    public func setTotalInstallments(_ total: Int, at index: Int) {
        guard rows.indices.contains(index) else { return }
        let counts = InstallmentPlan.supportedCounts
        let clamped = min(max(total, counts.lowerBound), counts.upperBound)
        rows[index].totalInstallments = clamped
        rows[index].currentInstallment = min(max(rows[index].currentInstallment, 1), clamped)
    }

    /// Sets the current installment of the row at `index`, clamped to `1...totalInstallments`.
    public func setCurrentInstallment(_ current: Int, at index: Int) {
        guard rows.indices.contains(index) else { return }
        rows[index].currentInstallment = min(max(current, 1), max(rows[index].totalInstallments, 1))
    }

    /// The row as a candidate (title as merchant, parsed amount), or `nil` when the amount is not a number.
    public func candidate(for row: StatementReviewRow) -> InstallmentCandidate? {
        guard let amount = AmountInput.parse(row.amountText, locale: locale) else { return nil }
        return InstallmentCandidate(
            id: row.id, merchant: row.title, installmentAmount: amount,
            currentInstallment: row.currentInstallment, totalInstallments: row.totalInstallments
        )
    }

    /// `true` when the row looks like an installment that is already saved, on the chosen card.
    public func isPossibleDuplicate(_ row: StatementReviewRow) -> Bool {
        candidate(for: row)?.isPossibleDuplicate(of: existing, cardID: cardID) ?? false
    }

    /// The payments left from the statement month on, counting this one (`3/6` → 4).
    public func remainingInstallments(of row: StatementReviewRow) -> Int {
        numbers(of: row).remainingInstallments
    }

    /// The month of the row's last payment, or `nil` when its installment numbers are invalid.
    public func endMonth(of row: StatementReviewRow) -> YearMonth? {
        numbers(of: row).endMonth(statementMonth: statementMonth)
    }

    // Kalan taksit ve bitiş ayı yalnızca taksit numaralarına bağlıdır; tutar geçersizken de gösterilir.
    private func numbers(of row: StatementReviewRow) -> InstallmentCandidate {
        InstallmentCandidate(
            id: row.id, merchant: row.title, installmentAmount: 0,
            currentInstallment: row.currentInstallment, totalInstallments: row.totalInstallments
        )
    }

    /// The first problem of the row (title, amount, installment numbers, months), or `nil` when it can be added.
    public func errorMessage(for row: StatementReviewRow) -> String? {
        guard let candidate = candidate(for: row) else { return AmountInput.missingMessage(for: row.amountText, locale: locale) }
        guard candidate.hasValidInstallmentNumbers else {
            let range = InstallmentPlan.supportedCounts
            return String(
                localized: "Use \(range.lowerBound) to \(range.upperBound) installments, the current one not above the total.",
                bundle: .module
            )
        }
        guard let draft = candidate.draft(cardID: cardID, paymentDay: todayDay, statementMonth: statementMonth) else {
            return String(localized: "The installments fall outside the supported months.", bundle: .module)
        }
        switch draft.errors.first {
        case .titleEmpty: return String(localized: "Enter a title.", bundle: .module)
        case .titleTooLong: return String(localized: "Use at most \(InstallmentItem.maxTitleLength) characters.", bundle: .module)
        case .amountMissing: return AmountInput.missingMessage(for: row.amountText, locale: locale)
        case .amountNotPositive: return AmountInput.notPositiveMessage
        case .countOutOfRange, .firstMonthOutOfRange, .paymentDayOutOfRange:
            return String(localized: "The installments fall outside the supported months.", bundle: .module)
        case nil: return nil
        }
    }

    /// `true` when the row can be added.
    public func isValid(_ row: StatementReviewRow) -> Bool {
        item(for: row) != nil
    }

    /// `true` when at least one row is selected and every selected row is valid.
    public var canSave: Bool {
        let selected = rows.filter(\.isSelected)
        return !selected.isEmpty && selected.allSatisfy(isValid)
    }

    // MARK: Kart ve ay

    /// The month as `"October 2026"`, like Home.
    public func title(of month: YearMonth) -> String {
        HomeViewModel.title(of: month)
    }

    /// The chosen card's name, or "No card".
    public var cardTitle: String {
        cards.first { $0.id == cardID }?.name ?? String(localized: "No card", bundle: .module)
    }

    // MARK: Kaydetme

    /// Saves every selected row as a new installment and remembers the card.
    ///
    /// All selected rows are validated first; if one is invalid nothing is saved and `false` is returned.
    /// A repository error removes the installments saved so far, sets ``failureMessage`` and returns `false`.
    @discardableResult
    public func save() -> Bool {
        let items = rows.filter(\.isSelected).compactMap(item(for:))
        guard !items.isEmpty, items.count == selectedCount else { return false }
        var saved: [InstallmentItem.ID] = []
        do {
            for item in items {
                try repository.save(item)
                saved.append(item.id)
            }
        } catch {
            // Yarım kalan içe aktarma geri alınır: ya hepsi eklenir ya hiçbiri.
            for id in saved { try? repository.deleteInstallment(id: id) }
            failureMessage = AddInstallmentViewModel.saveErrorMessage
            return false
        }
        failureMessage = nil
        lastUsedCard.cardID = cardID
        return true
    }

    private func item(for row: StatementReviewRow) -> InstallmentItem? {
        candidate(for: row)?.makeItem(cardID: cardID, paymentDay: todayDay, statementMonth: statementMonth)
    }
}
