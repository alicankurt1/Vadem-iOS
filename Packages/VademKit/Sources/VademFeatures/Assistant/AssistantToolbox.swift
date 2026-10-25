import Foundation
import VademCore

/// The five read-only tools of the assistant, free of FoundationModels so they are testable anywhere.
///
/// Each method takes the model's raw argument strings, parses them and returns the
/// ``AssistantQueries`` result as JSON text. Malformed arguments give `{"error": …}`, never a throw.
public struct AssistantToolbox: Sendable {
    private struct ErrorResult: Encodable {
        let error: String
    }

    private struct NoNextPayment: Encodable {
        let nextPayment: String?
        let note: String

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNil(forKey: .nextPayment)
            try container.encode(note, forKey: .note)
        }

        enum CodingKeys: String, CodingKey { case nextPayment, note }
    }

    private let queries: AssistantQueries
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    /// Creates a toolbox over `queries`; `now` and `calendar` define "today" and "this month".
    public init(
        queries: AssistantQueries,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.queries = queries
        self.calendar = calendar
        self.now = now
    }

    // MARK: Argument parsing

    /// Parses a month argument: `"2026-03"`, `"2026-3"` or `"2026/03"`. Empty text means the current month.
    /// Returns `nil` for anything else (out-of-range months, words, extra parts).
    public static func parseMonth(_ raw: String, now: Date, calendar: Calendar = .current) -> YearMonth? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return YearMonth(date: now, calendar: calendar) }
        let parts = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "-" || $0 == "/" })
        guard parts.count == 2,
              parts[0].count == 4, parts[1].count <= 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1])
        else { return nil }
        return YearMonth(year: year, month: month)
    }

    /// Cleans a card name argument; `nil` when nothing is left.
    public static func parseCardName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    // MARK: Tools

    /// Tool `monthTotal`: what is due in a month.
    public func monthTotal(month: String) -> String {
        guard let month = Self.parseMonth(month, now: now(), calendar: calendar) else { return Self.monthError }
        return Self.json(queries.monthTotal(month))
    }

    /// Tool `paymentsInMonth`: the payments due in a month.
    public func payments(month: String) -> String {
        guard let month = Self.parseMonth(month, now: now(), calendar: calendar) else { return Self.monthError }
        return Self.json(queries.payments(in: month))
    }

    /// Tool `nextPayment`: the next payment from today.
    public func nextPayment() -> String {
        guard let next = queries.nextPayment(after: now(), calendar: calendar) else {
            return Self.json(NoNextPayment(nextPayment: nil, note: "No upcoming payment."))
        }
        return Self.json(next)
    }

    /// Tool `cardTotal`: what one card is due in a month.
    public func cardTotal(cardName: String, month: String) -> String {
        guard let name = Self.parseCardName(cardName) else {
            return Self.json(ErrorResult(error: "cardName must not be empty."))
        }
        guard let month = Self.parseMonth(month, now: now(), calendar: calendar) else { return Self.monthError }
        return Self.json(queries.cardTotal(cardNamed: name, in: month))
    }

    /// Tool `debtFreeMonth`: the last month with an installment payment.
    public func debtFreeMonth() -> String {
        Self.json(queries.debtFreeMonth)
    }

    // MARK: Output

    private static var monthError: String {
        json(ErrorResult(error: "month must look like YYYY-MM, for example 2026-03, or be empty for the current month."))
    }

    private static func json(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            return #"{"error":"Could not encode the result."}"#
        }
        return text
    }
}
