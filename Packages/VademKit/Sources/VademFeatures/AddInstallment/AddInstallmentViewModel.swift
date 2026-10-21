import Foundation
import Observation
import VademCore

/// Drives the add-installment form: field values, per-field errors and saving through ``PaymentRepository``.
///
/// Validation comes from ``InstallmentDraft``. A field's error is shown only after the field
/// was changed, or after ``showAllErrors()`` / a failed ``save()``.
@MainActor
@Observable
public final class AddInstallmentViewModel: Identifiable {
    /// The message shown when the cards could not be loaded.
    public nonisolated static let cardsLoadErrorMessage = "Your cards could not be loaded."
    /// The message shown when saving failed.
    public nonisolated static let saveErrorMessage = "The installment could not be saved. Please try again."
    /// How many months before the initial month the first-month picker offers.
    public nonisolated static let monthsBefore = InstallmentPlan.supportedCounts.upperBound - 1
    /// How many months after the initial month the first-month picker offers.
    public nonisolated static let monthsAfter = 12

    /// The title as typed.
    public var title: String = "" { didSet { touched.insert(.title) } }
    /// The chosen card, or `nil` while none is chosen.
    public var cardID: Card.ID? { didSet { touched.insert(.card) } }
    /// The total as typed, with the locale's decimal separator (e.g. `"1.499,90"` in Turkish).
    public var amountText: String = "" { didSet { touched.insert(.amount) } }
    /// The number of monthly payments.
    public var count: Int = InstallmentPlan.supportedCounts.lowerBound { didSet { touched.insert(.count) } }
    /// The month of the first payment.
    public var firstMonth: YearMonth { didSet { touched.insert(.firstMonth) } }

    /// The cards to choose from, in the repository's order.
    public private(set) var cards: [Card] = []
    /// The months the first-month picker offers, in order; contains the initial month.
    public let firstMonthOptions: [YearMonth]
    /// A message for a load or save failure, or `nil`.
    public private(set) var failureMessage: String?

    @ObservationIgnored private let repository: any PaymentRepository
    @ObservationIgnored private let locale: Locale
    // Değiştirilmiş alanlar; hata sadece bunlarda (veya hepsi açılınca) gösterilir.
    private var touched: Set<InstallmentDraft.Field> = []
    private var showsAllErrors = false

    /// Creates an empty form whose first month is `initialMonth`, and loads the cards.
    ///
    /// `locale` decides the decimal and grouping separators of ``amountText``.
    public init(repository: any PaymentRepository, initialMonth: YearMonth, locale: Locale = .current) {
        self.repository = repository
        self.locale = locale
        self.firstMonth = initialMonth
        self.cardID = nil
        self.firstMonthOptions = Self.months(around: initialMonth)
        do {
            cards = try repository.cards()
        } catch {
            failureMessage = Self.cardsLoadErrorMessage
        }
    }

    /// The draft built from the current field values.
    public var draft: InstallmentDraft {
        InstallmentDraft(
            title: title,
            cardID: cardID,
            total: Self.parseAmount(amountText, locale: locale),
            count: count,
            firstMonth: firstMonth
        )
    }

    /// `true` when the draft is valid, so Save can be enabled.
    public var canSave: Bool {
        draft.isValid
    }

    /// The error message to show under `field`, or `nil` when it is valid or not yet shown.
    public func errorMessage(for field: InstallmentDraft.Field) -> String? {
        guard showsAllErrors || touched.contains(field), let error = draft.error(for: field) else { return nil }
        return message(for: error)
    }

    /// Shows the errors of every field, touched or not.
    public func showAllErrors() {
        showsAllErrors = true
    }

    /// Saves the draft as a new installment.
    ///
    /// Returns `true` on success. An invalid draft shows every error and returns `false`;
    /// a repository error sets ``failureMessage`` and returns `false`.
    @discardableResult
    public func save() -> Bool {
        guard let item = draft.makeItem() else {
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

    /// The month as `"October 2026"`, like Home.
    public func title(of month: YearMonth) -> String {
        HomeViewModel.title(of: month)
    }

    /// Parses `text` as a decimal number written with `locale`'s separators.
    ///
    /// Only ASCII digits, the locale's decimal separator (at most once) and a leading minus
    /// sign are accepted; surrounding whitespace is ignored. Returns `nil` for empty text or
    /// anything else, including grouping separators (`"1.499,90"` in Turkish) and a `.` when
    /// the locale uses `,`.
    public nonisolated static func parseAmount(_ text: String, locale: Locale) -> Decimal? {
        let decimalSeparator = locale.decimalSeparator ?? "."
        // Gruplama ayracı kabul edilmez: Türkçede "1499.90" sessizce 149990 olmasın, hata gösterilsin.
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNegative = body.hasPrefix("-")
        if isNegative { body.removeFirst() }
        let parts = body.components(separatedBy: decimalSeparator)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              parts.contains(where: { !$0.isEmpty }) else {
            return nil
        }
        // Locale'den bağımsız biçime çevrilip Decimal'e dönüştürülür; Double hiç kullanılmaz.
        let normalized = (isNegative ? "-" : "") + parts.map { $0.isEmpty ? "0" : $0 }.joined(separator: ".")
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func message(for error: InstallmentDraft.ValidationError) -> String {
        switch error {
        case .titleEmpty:
            return "Enter a title."
        case .titleTooLong:
            return "Use at most \(InstallmentItem.maxTitleLength) characters."
        case .cardMissing:
            return cards.isEmpty ? "Add a card first." : "Choose a card."
        case .amountMissing:
            let isEmpty = amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return isEmpty ? "Enter an amount." : "Enter a number like 1499\(locale.decimalSeparator ?? ".")90."
        case .amountNotPositive:
            return "Amount must be greater than zero."
        case .countOutOfRange:
            let range = InstallmentPlan.supportedCounts
            return "Choose \(range.lowerBound) to \(range.upperBound) installments."
        case .firstMonthOutOfRange:
            return "The last installment must be in December 9999 or earlier."
        }
    }

    // Başlangıç ayının çevresindeki aylar; desteklenen aralığın dışına taşmaz.
    private nonisolated static func months(around month: YearMonth) -> [YearMonth] {
        let first = YearMonth(year: YearMonth.supportedYears.lowerBound, month: 1)!
        let last = YearMonth(year: YearMonth.supportedYears.upperBound, month: 12)!
        let before = min(monthsBefore, first.months(until: month))
        let after = min(monthsAfter, month.months(until: last))
        return (-before...after).map { month.adding(months: $0) }
    }
}
