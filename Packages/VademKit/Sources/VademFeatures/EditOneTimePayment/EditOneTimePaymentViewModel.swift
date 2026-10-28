import Foundation
import Observation
import VademCore

/// Drives the edit form of a saved one-time payment: field values, per-field errors, saving and deleting
/// through ``PaymentRepository``.
///
/// Fields start with the payment's values; validation comes from ``OneTimePaymentDraft``. A field's
/// error is shown only after the field was changed, or after ``showAllErrors()`` / a failed ``save()``.
/// ``save()`` replaces the payment (same `id`) and ``delete()`` removes it. Changing ``dueMonth``
/// clamps ``dueDay`` to the month's days.
@MainActor
@Observable
public final class EditOneTimePaymentViewModel: Identifiable {
    /// The message shown when saving failed.
    public nonisolated static var saveErrorMessage: String {
        String(localized: "The payment could not be saved. Please try again.", bundle: .module)
    }
    /// The message shown when deleting failed.
    public nonisolated static var deleteErrorMessage: String {
        String(localized: "The payment could not be deleted. Please try again.", bundle: .module)
    }
    /// How many months before the payment's month the due-month picker offers.
    public nonisolated static let monthsBefore = 24
    /// How many months after the payment's month the due-month picker offers.
    public nonisolated static let monthsAfter = 24

    /// The title as typed.
    public var title: String { didSet { touched.insert(.title) } }
    /// The chosen card, or `nil` when the payment is not charged to a card.
    public var cardID: Card.ID? { didSet { touched.insert(.card) } }
    /// The amount as typed, with the locale's decimal separator (e.g. `"1500,5"` in Turkish).
    public var amountText: String { didSet { touched.insert(.amount) } }
    /// The month of the due date; a change clamps ``dueDay`` to the month's days.
    public var dueMonth: YearMonth {
        didSet {
            touched.insert(.dueDate)
            if dueDay > dueMonth.numberOfDays { dueDay = dueMonth.numberOfDays }
        }
    }
    /// The day of ``dueMonth`` the payment is due on.
    public var dueDay: Int { didSet { touched.insert(.dueDate) } }

    /// The cards to choose from, in the repository's order.
    public private(set) var cards: [Card] = []
    /// The months the due-month picker offers, in order; contains the payment's month.
    public let monthOptions: [YearMonth]
    /// A message for a load, save or delete failure, or `nil`.
    public private(set) var failureMessage: String?
    /// The id of the payment being edited.
    public let editingID: OneTimePaymentItem.ID

    @ObservationIgnored private let repository: any PaymentRepository
    @ObservationIgnored private let locale: Locale
    // Değiştirilmiş alanlar; hata sadece bunlarda (veya hepsi açılınca) gösterilir.
    private var touched: Set<OneTimePaymentDraft.Field> = []
    private var showsAllErrors = false

    /// Creates a form that edits `item`: every field starts with its value, and the cards are loaded.
    ///
    /// `locale` decides the decimal separator of ``amountText``. No error shows until a field changes.
    public init(repository: any PaymentRepository, editing item: OneTimePaymentItem, locale: Locale = .current) {
        self.repository = repository
        self.locale = locale
        self.editingID = item.id
        self.title = item.title
        self.cardID = item.cardID
        self.amountText = AmountInput.text(for: item.amount.amount, locale: locale)
        self.dueMonth = item.dueMonth
        self.dueDay = item.dueDay
        self.monthOptions = MonthOptions.months(around: item.dueMonth, before: Self.monthsBefore, after: Self.monthsAfter)
        loadCards()
        // Ön doldurma kullanıcı değişikliği sayılmaz.
        touched.removeAll()
    }

    private func loadCards() {
        do {
            cards = try repository.cards()
        } catch {
            failureMessage = AddSubscriptionViewModel.cardsLoadErrorMessage
        }
    }

    /// The draft built from the current field values.
    public var draft: OneTimePaymentDraft {
        OneTimePaymentDraft(
            title: title, cardID: cardID, amount: AmountInput.parse(amountText, locale: locale),
            dueMonth: dueMonth, dueDay: dueDay
        )
    }

    /// `true` when the draft is valid, so Save can be enabled.
    public var canSave: Bool { draft.isValid }

    /// The error message to show under `field`, or `nil` when it is valid or not yet shown.
    public func errorMessage(for field: OneTimePaymentDraft.Field) -> String? {
        guard showsAllErrors || touched.contains(field), let error = draft.error(for: field) else { return nil }
        return message(for: error)
    }

    /// Shows the errors of every field, touched or not.
    public func showAllErrors() {
        showsAllErrors = true
    }

    /// Saves the draft under ``editingID``, replacing the saved payment.
    ///
    /// Returns `true` on success. An invalid draft shows every error and returns `false`;
    /// a repository error sets ``failureMessage`` and returns `false`.
    @discardableResult
    public func save() -> Bool {
        guard let item = draft.makeItem(id: editingID) else {
            showAllErrors()
            return false
        }
        do {
            try repository.save(item)
            failureMessage = nil
            return true
        } catch {
            failureMessage = Self.saveErrorMessage
            return false
        }
    }

    /// Deletes the edited payment. Returns `true` on success; a repository error sets
    /// ``failureMessage`` and returns `false`.
    @discardableResult
    public func delete() -> Bool {
        do {
            try repository.deleteOneTimePayment(id: editingID)
            failureMessage = nil
            return true
        } catch {
            failureMessage = Self.deleteErrorMessage
            return false
        }
    }

    /// The month as `"October 2026"`, like Home.
    public func title(of month: YearMonth) -> String {
        HomeViewModel.title(of: month)
    }

    private func message(for error: OneTimePaymentDraft.ValidationError) -> String {
        switch error {
        case .titleEmpty:
            return String(localized: "Enter a title.", bundle: .module)
        case .titleTooLong:
            return String(localized: "Use at most \(OneTimePaymentItem.maxTitleLength) characters.", bundle: .module)
        case .amountMissing:
            return AmountInput.missingMessage(for: amountText, locale: locale)
        case .amountNotPositive:
            return AmountInput.notPositiveMessage
        case .dueDayOutOfRange:
            return String(localized: "Choose a day from 1 to \(dueMonth.numberOfDays).", bundle: .module)
        }
    }
}
