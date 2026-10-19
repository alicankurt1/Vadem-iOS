import Foundation

/// A tracked installment purchase: an ``InstallmentPlan`` with identity, a title and its card.
///
/// An installment always belongs to a card.
public struct InstallmentItem: Sendable, Hashable, Identifiable {
    /// The maximum length of ``title``, in characters, after trimming.
    public static let maxTitleLength = 60

    /// A stable identifier for storage.
    public let id: UUID
    /// The display title, trimmed; never empty and at most ``maxTitleLength`` characters.
    public let title: String
    /// The card the installments are charged to.
    public let cardID: Card.ID
    /// The payment schedule.
    public let plan: InstallmentPlan

    /// Creates an item, or returns `nil` unless the trimmed `title` is non-empty
    /// and at most ``maxTitleLength`` characters.
    public init?(id: UUID = UUID(), title: String, cardID: Card.ID, plan: InstallmentPlan) {
        guard let trimmed = ItemTitle.validated(title, maxLength: InstallmentItem.maxTitleLength) else {
            return nil
        }
        self.id = id
        self.title = trimmed
        self.cardID = cardID
        self.plan = plan
    }
}

// Çözümlemede de failable init'in kuralları geçerli: geçersiz başlık reddedilir.
extension InstallmentItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, cardID, plan
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let title = try container.decode(String.self, forKey: .title)
        let cardID = try container.decode(Card.ID.self, forKey: .cardID)
        let plan = try container.decode(InstallmentPlan.self, forKey: .plan)
        guard let item = InstallmentItem(id: id, title: title, cardID: cardID, plan: plan) else {
            throw DecodingError.dataCorruptedError(
                forKey: .title, in: container,
                debugDescription: "Invalid installment title \"\(title)\""
            )
        }
        self = item
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(cardID, forKey: .cardID)
        try container.encode(plan, forKey: .plan)
    }
}
