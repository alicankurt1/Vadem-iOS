import Foundation

/// Errors a ``PaymentRepository`` throws when a change would break a rule.
public enum RepositoryError: Error, Sendable, Hashable {
    /// The card is still referenced by an installment or a subscription.
    case cardInUse
    /// The item refers to a card that has not been saved.
    case unknownCard
}

/// Saves and loads cards, installments and subscriptions.
///
/// One protocol for all three keeps the shared rule in one place: a card that is
/// still in use cannot be deleted. ``InMemoryPaymentRepository`` is the reference
/// implementation; every implementation must behave the same.
///
/// Text ordering in every list uses `String.caseInsensitiveCompare(_:)` (not localized,
/// e.g. not `localizedStandardCompare(_:)`); equal texts are ordered by `id.uuidString`.
@MainActor
public protocol PaymentRepository {
    /// All cards, sorted by name with `caseInsensitiveCompare(_:)`, then by `id.uuidString`.
    func cards() throws -> [Card]
    /// Inserts `card`, or replaces the saved card with the same `id`.
    func save(_ card: Card) throws
    /// Deletes the card with `id`; an unknown `id` is a no-op.
    /// - Throws: ``RepositoryError/cardInUse`` if an installment or a subscription refers to it.
    func deleteCard(id: Card.ID) throws

    /// All installments, sorted by `plan.firstMonth`, then by title with
    /// `caseInsensitiveCompare(_:)`, then by `id.uuidString`.
    func installments() throws -> [InstallmentItem]
    /// Inserts `item`, or replaces the saved installment with the same `id`.
    /// - Throws: ``RepositoryError/unknownCard`` if `item.cardID` is not a saved card.
    func save(_ item: InstallmentItem) throws
    /// Deletes the installment with `id`; an unknown `id` is a no-op.
    func deleteInstallment(id: InstallmentItem.ID) throws

    /// All subscriptions, sorted by title with `caseInsensitiveCompare(_:)`, then by `id.uuidString`.
    func subscriptions() throws -> [SubscriptionItem]
    /// Inserts `item`, or replaces the saved subscription with the same `id`.
    /// - Throws: ``RepositoryError/unknownCard`` if `item.cardID` is set and not a saved card.
    func save(_ item: SubscriptionItem) throws
    /// Deletes the subscription with `id`; an unknown `id` is a no-op.
    func deleteSubscription(id: SubscriptionItem.ID) throws
}
