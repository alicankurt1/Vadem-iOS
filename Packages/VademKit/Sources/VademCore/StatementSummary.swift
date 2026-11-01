import Foundation

/// The statement's own debt: what the whole statement asks for and when it is due.
///
/// ``StatementParser/parseStatement(lines:)`` finds it from the statement total (`Dönem Borcunuz`, else
/// `Toplam Borcunuz`) and the due date (`Son Ödeme Tarihi`); the minimum payment is never used.
public struct StatementSummary: Sendable, Hashable {
    /// The statement total in TRY; always greater than zero when parsed.
    public var total: Decimal
    /// The due date of the statement.
    public var dueDate: StatementDate

    /// Creates a summary.
    public init(total: Decimal, dueDate: StatementDate) {
        self.total = total
        self.dueDate = dueDate
    }
}

/// Everything ``StatementParser/parseStatement(lines:)`` finds in a statement.
public struct StatementParseResult: Sendable, Hashable {
    /// The installment candidates, in the order they appear.
    public var candidates: [InstallmentCandidate]
    /// The statement total and due date, or `nil` when either one was not found.
    public var summary: StatementSummary?

    /// Creates a result.
    public init(candidates: [InstallmentCandidate], summary: StatementSummary? = nil) {
        self.candidates = candidates
        self.summary = summary
    }
}
