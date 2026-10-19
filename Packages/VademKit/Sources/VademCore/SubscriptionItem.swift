import Foundation

/// A tracked subscription: a ``Subscription`` with identity, a title and an optional card.
public struct SubscriptionItem: Sendable, Hashable, Identifiable {
    /// The maximum length of ``title``, in characters, after trimming.
    public static let maxTitleLength = 60

    /// A stable identifier for storage.
    public let id: UUID
    /// The display title, trimmed; never empty and at most ``maxTitleLength`` characters.
    public let title: String
    /// The card the subscription is charged to, or `nil` when it is paid some other way.
    public let cardID: Card.ID?
    /// The billing schedule.
    public let subscription: Subscription

    /// Creates an item, or returns `nil` unless the trimmed `title` is non-empty
    /// and at most ``maxTitleLength`` characters.
    public init?(id: UUID = UUID(), title: String, cardID: Card.ID?, subscription: Subscription) {
        guard let trimmed = ItemTitle.validated(title, maxLength: SubscriptionItem.maxTitleLength) else {
            return nil
        }
        self.id = id
        self.title = trimmed
        self.cardID = cardID
        self.subscription = subscription
    }
}

// Çözümlemede de failable init'in kuralları geçerli: geçersiz başlık reddedilir.
extension SubscriptionItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, cardID, subscription
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let title = try container.decode(String.self, forKey: .title)
        let cardID = try container.decodeIfPresent(Card.ID.self, forKey: .cardID)
        let subscription = try container.decode(Subscription.self, forKey: .subscription)
        guard let item = SubscriptionItem(id: id, title: title, cardID: cardID, subscription: subscription) else {
            throw DecodingError.dataCorruptedError(
                forKey: .title, in: container,
                debugDescription: "Invalid subscription title \"\(title)\""
            )
        }
        self = item
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(cardID, forKey: .cardID)
        try container.encode(subscription, forKey: .subscription)
    }
}
