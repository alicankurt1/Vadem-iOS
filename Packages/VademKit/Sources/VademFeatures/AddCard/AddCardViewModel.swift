import Foundation
import Observation
import VademCore

/// Drives the add-card form: field values, per-field errors and saving through ``PaymentRepository``.
///
/// Validation comes from ``CardDraft``. A field's error is shown only after the field
/// was changed, or after ``showAllErrors()`` / a failed ``save()``.
@MainActor
@Observable
public final class AddCardViewModel: Identifiable {
    /// The message shown when saving failed.
    public nonisolated static let saveErrorMessage = "The card could not be saved. Please try again."

    /// The name as typed.
    public var name: String = "" { didSet { touched.insert(.name) } }
    /// The statement day as typed (digits only are accepted, e.g. `"28"`).
    public var statementDayText: String = "" { didSet { touched.insert(.statementDay) } }
    /// The due day as typed (digits only are accepted, e.g. `"8"`).
    public var dueDayText: String = "" { didSet { touched.insert(.dueDay) } }

    /// A message for a save failure, or `nil`.
    public private(set) var failureMessage: String?
    /// The card stored by the last successful ``save()``, or `nil` before that.
    public private(set) var savedCard: Card?

    @ObservationIgnored private let repository: any PaymentRepository
    // Değiştirilmiş alanlar; hata sadece bunlarda (veya hepsi açılınca) gösterilir.
    private var touched: Set<CardDraft.Field> = []
    private var showsAllErrors = false

    /// Creates an empty form that saves to `repository`.
    public init(repository: any PaymentRepository) {
        self.repository = repository
    }

    /// The draft built from the current field values.
    public var draft: CardDraft {
        CardDraft(
            name: name,
            statementDay: Self.parseDay(statementDayText),
            dueDay: Self.parseDay(dueDayText)
        )
    }

    /// `true` when the draft is valid, so Save can be enabled.
    public var canSave: Bool {
        draft.isValid
    }

    /// The error message to show under `field`, or `nil` when it is valid or not yet shown.
    public func errorMessage(for field: CardDraft.Field) -> String? {
        guard showsAllErrors || touched.contains(field), let error = draft.error(for: field) else { return nil }
        return Self.message(for: error)
    }

    /// Shows the errors of every field, touched or not.
    public func showAllErrors() {
        showsAllErrors = true
    }

    /// Saves the draft as a new card and stores it in ``savedCard``.
    ///
    /// Returns `true` on success. An invalid draft shows every error and returns `false`;
    /// a repository error sets ``failureMessage`` and returns `false`.
    @discardableResult
    public func save() -> Bool {
        guard let card = draft.makeCard() else {
            showAllErrors()
            return false
        }
        do {
            try repository.save(card)
            failureMessage = nil
            savedCard = card
            return true
        } catch {
            failureMessage = Self.saveErrorMessage
            return false
        }
    }

    /// Parses `text` as a day number: ASCII digits only, surrounding whitespace ignored.
    ///
    /// Returns `nil` for empty text, anything else, or a number too large for `Int`.
    /// The range is not checked here; ``CardDraft`` does that.
    public nonisolated static func parseDay(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // "+5", "-1" veya "٣" gibi girdiler kabul edilmez; yalnızca ASCII rakam.
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(trimmed)
    }

    private nonisolated static func message(for error: CardDraft.ValidationError) -> String {
        let days = Card.supportedDays
        switch error {
        case .nameEmpty:
            return "Enter a card name."
        case .nameTooLong:
            return "Use at most \(Card.maxNameLength) characters."
        case .statementDayOutOfRange:
            return "Enter a statement day from \(days.lowerBound) to \(days.upperBound)."
        case .dueDayOutOfRange:
            return "Enter a due day from \(days.lowerBound) to \(days.upperBound)."
        }
    }
}
