import Foundation

/// A tracked installment purchase: an ``InstallmentPlan`` with identity, a title and an optional card.
///
/// With a card the payments follow the card's statement and due days. Without a card each
/// payment is due on ``paymentDay`` of its month (clamped to the month's last day, like
/// ``Subscription/chargeDay(in:)``).
public struct InstallmentItem: Sendable, Hashable, Identifiable {
    /// The maximum length of ``title``, in characters, after trimming.
    public static let maxTitleLength = 60
    /// The supported payment days of a card-less installment; the same as ``Subscription/supportedRenewalDays``.
    public static let supportedPaymentDays: ClosedRange<Int> = Subscription.supportedRenewalDays

    /// A stable identifier for storage.
    public let id: UUID
    /// The display title, trimmed; never empty and at most ``maxTitleLength`` characters.
    public let title: String
    /// The card the installments are charged to, or `nil` when they are paid some other way.
    public let cardID: Card.ID?
    /// The day of the month a card-less installment is paid on, in ``supportedPaymentDays``;
    /// `nil` when ``cardID`` is set (the card decides the due day).
    public let paymentDay: Int?
    /// The payment schedule.
    public let plan: InstallmentPlan

    /// Creates an item, or returns `nil` unless the trimmed `title` is non-empty
    /// and at most ``maxTitleLength`` characters, and exactly one of `cardID` and `paymentDay`
    /// is set, with `paymentDay` in ``supportedPaymentDays``.
    public init?(id: UUID = UUID(), title: String, cardID: Card.ID?, paymentDay: Int? = nil, plan: InstallmentPlan) {
        guard let trimmed = ItemTitle.validated(title, maxLength: InstallmentItem.maxTitleLength) else {
            return nil
        }
        // Ödeme günü ya karttan gelir ya kalemin kendisinden; ikisi birden ya da hiçbiri olamaz.
        switch (cardID, paymentDay) {
        case (.some, nil):
            break
        case (nil, .some(let day)) where InstallmentItem.supportedPaymentDays.contains(day):
            break
        default:
            return nil
        }
        self.id = id
        self.title = trimmed
        self.cardID = cardID
        self.paymentDay = paymentDay
        self.plan = plan
    }
}

// Çözümlemede de failable init'in kuralları geçerli: geçersiz başlık veya kart/gün çifti reddedilir.
// Eski veride `paymentDay` yoktur ve `cardID` her zaman doludur; ikisi de isteğe bağlı okunur.
extension InstallmentItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, cardID, paymentDay, plan
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let title = try container.decode(String.self, forKey: .title)
        let cardID = try container.decodeIfPresent(Card.ID.self, forKey: .cardID)
        let paymentDay = try container.decodeIfPresent(Int.self, forKey: .paymentDay)
        let plan = try container.decode(InstallmentPlan.self, forKey: .plan)
        guard let item = InstallmentItem(id: id, title: title, cardID: cardID, paymentDay: paymentDay, plan: plan) else {
            let dayText = paymentDay.map(String.init) ?? "nil"
            throw DecodingError.dataCorruptedError(
                forKey: .title, in: container,
                debugDescription: "Invalid installment: title \"\(title)\", "
                    + "cardID \(cardID?.uuidString ?? "nil"), paymentDay \(dayText)"
            )
        }
        self = item
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(cardID, forKey: .cardID)
        try container.encodeIfPresent(paymentDay, forKey: .paymentDay)
        try container.encode(plan, forKey: .plan)
    }
}
