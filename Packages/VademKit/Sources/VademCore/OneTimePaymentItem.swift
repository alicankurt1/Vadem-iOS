import Foundation

/// A tracked one-time payment: a single amount due on one calendar day, with an optional card.
///
/// The due date is a calendar day (``dueMonth`` + ``dueDay``) with no time or time zone,
/// so it never moves to another day when the device's time zone changes.
public struct OneTimePaymentItem: Sendable, Hashable, Identifiable {
    /// The maximum length of ``title``, in characters, after trimming.
    public static let maxTitleLength = 60

    /// A stable identifier for storage.
    public let id: UUID
    /// The display title, trimmed; never empty and at most ``maxTitleLength`` characters.
    public let title: String
    /// The card the payment is charged to, or `nil` when it is paid some other way.
    public let cardID: Card.ID?
    /// The paid amount; always greater than zero.
    public let amount: Money
    /// The month of the due date.
    public let dueMonth: YearMonth
    /// The day of ``dueMonth`` the payment is due on, in `1...dueMonth.numberOfDays`.
    public let dueDay: Int

    /// Creates an item, or returns `nil` unless the trimmed `title` is non-empty and at most
    /// ``maxTitleLength`` characters, `amount` is greater than zero and `dueDay` is a day
    /// of `dueMonth` (e.g. February 30 is rejected, not clamped).
    public init?(id: UUID = UUID(), title: String, cardID: Card.ID?, amount: Money, dueMonth: YearMonth, dueDay: Int) {
        guard let trimmed = ItemTitle.validated(title, maxLength: OneTimePaymentItem.maxTitleLength),
              amount > .zero,
              (1...dueMonth.numberOfDays).contains(dueDay) else {
            return nil
        }
        self.id = id
        self.title = trimmed
        self.cardID = cardID
        self.amount = amount
        self.dueMonth = dueMonth
        self.dueDay = dueDay
    }
}

// Çözümlemede de failable init'in kuralları geçerli: geçersiz başlık, tutar veya gün reddedilir.
// Hata birden fazla alana bağlı olabildiği için tek bir anahtara değil, kalemin tamamına bağlanır.
extension OneTimePaymentItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, cardID, amount, dueMonth, dueDay
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let title = try container.decode(String.self, forKey: .title)
        let cardID = try container.decodeIfPresent(Card.ID.self, forKey: .cardID)
        let amount = try container.decode(Money.self, forKey: .amount)
        let dueMonth = try container.decode(YearMonth.self, forKey: .dueMonth)
        let dueDay = try container.decode(Int.self, forKey: .dueDay)
        guard let item = OneTimePaymentItem(
            id: id, title: title, cardID: cardID, amount: amount, dueMonth: dueMonth, dueDay: dueDay
        ) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid one-time payment: title \"\(title)\", amount \(amount.amount), "
                        + "due \(dueMonth.year)-\(dueMonth.month)-\(dueDay)"
                )
            )
        }
        self = item
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(cardID, forKey: .cardID)
        try container.encode(amount, forKey: .amount)
        try container.encode(dueMonth, forKey: .dueMonth)
        try container.encode(dueDay, forKey: .dueDay)
    }
}
