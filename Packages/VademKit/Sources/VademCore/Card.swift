import Foundation

/// A credit card with its monthly statement day and payment due day.
///
/// Only a display name and the two days are kept; the app never stores card numbers.
/// In months shorter than a day, that day falls on the month's last day
/// (day 31 → Feb 28, or Feb 29 in leap years; Apr 30).
public struct Card: Sendable, Hashable, Identifiable {
    /// A calendar day: a month and a day within it.
    public struct DueDate: Sendable, Hashable {
        /// The month of the due date.
        public let month: YearMonth
        /// The day of ``month``, already clamped to the month's last day.
        public let day: Int
    }

    /// The supported statement and due days.
    public static let supportedDays: ClosedRange<Int> = 1...31
    /// The maximum length of ``name``, in characters, after trimming.
    public static let maxNameLength = 40

    /// A stable identifier, so plans and storage can refer to the card.
    public let id: UUID
    /// The display name, trimmed; never empty and at most ``maxNameLength`` characters.
    public let name: String
    /// The day of the month the statement is cut, in ``supportedDays``.
    public let statementDay: Int
    /// The day of the month the payment is due, in ``supportedDays``.
    public let dueDay: Int

    /// Creates a card, or returns `nil` unless the trimmed `name` is non-empty and at most
    /// ``maxNameLength`` characters, and both days are in ``supportedDays``.
    public init?(id: UUID = UUID(), name: String, statementDay: Int, dueDay: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= Card.maxNameLength,
              Card.supportedDays.contains(statementDay), Card.supportedDays.contains(dueDay) else {
            return nil
        }
        self.id = id
        self.name = trimmed
        self.statementDay = statementDay
        self.dueDay = dueDay
    }

    /// The statement day in `month`, clamped to the month's last day.
    public func statementDay(in month: YearMonth) -> Int {
        min(statementDay, month.numberOfDays)
    }

    /// The due date for the statement cut in `month`: the first due day strictly after
    /// the statement date (same month if later, otherwise the next month).
    ///
    /// - Precondition: When the due date falls in the next month, that month's year
    ///   is in ``YearMonth/supportedYears``.
    public func dueDate(forStatementIn month: YearMonth) -> DueDate {
        // İki gün de önce bu aya kırpılır; aynı gün "sonra" sayılmaz, bu yüzden > kullanılır.
        let sameMonthDue = min(dueDay, month.numberOfDays)
        if sameMonthDue > statementDay(in: month) {
            return DueDate(month: month, day: sameMonthDue)
        }
        let next = month.adding(months: 1)
        return DueDate(month: next, day: min(dueDay, next.numberOfDays))
    }
}

// Çözümlemede de failable init'in kuralları geçerli: geçersiz kart reddedilir.
// İsim init'te kırpıldığı için kodlanan değer zaten kırpılmış; gidiş-dönüş birebir aynı kalır.
extension Card: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, statementDay, dueDay
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let statementDay = try container.decode(Int.self, forKey: .statementDay)
        let dueDay = try container.decode(Int.self, forKey: .dueDay)
        guard let card = Card(id: id, name: name, statementDay: statementDay, dueDay: dueDay) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid card: name \"\(name)\", statementDay \(statementDay), dueDay \(dueDay)"
                )
            )
        }
        self = card
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(statementDay, forKey: .statementDay)
        try container.encode(dueDay, forKey: .dueDay)
    }
}
