import Foundation
import Observation
import VademCore

/// Drives the Cards screen: every saved card, an empty state, and the add/edit card forms.
///
/// Cards are loaded on init in the repository's order (by name). Call ``refresh()`` after a
/// card form closes (saved, deleted or cancelled) so the list shows the change.
@MainActor
@Observable
public final class CardListViewModel: Identifiable {
    /// What the screen shows.
    public enum State: Sendable, Hashable {
        /// At least one card is saved.
        case loaded
        /// No card is saved.
        case empty
        /// The repository failed; `message` is shown to the user.
        case error(message: String)
    }

    /// The message of the ``State/error(message:)`` state.
    public nonisolated static var loadErrorMessage: String {
        String(localized: "Your cards could not be loaded.", bundle: .module)
    }

    /// The saved cards, in the repository's order; empty when there are none or after an error.
    public private(set) var cards: [Card] = []
    /// The current state.
    public private(set) var state: State = .empty

    /// `true` when no card is saved (and the repository did not fail): the screen shows its empty state.
    public var isEmpty: Bool { state == .empty }

    @ObservationIgnored private let repository: any PaymentRepository

    /// Creates the model on `repository` and loads the cards.
    public init(repository: any PaymentRepository) {
        self.repository = repository
        refresh()
    }

    /// Loads the cards again from the repository.
    public func refresh() {
        do {
            let loaded = try repository.cards()
            cards = loaded
            state = loaded.isEmpty ? .empty : .loaded
        } catch {
            // Hata durumunda eski liste gösterilmez.
            cards = []
            state = .error(message: Self.loadErrorMessage)
        }
    }

    /// A new, empty add-card form on the same repository. Call ``refresh()`` after it closes.
    public func makeAddCardModel() -> AddCardViewModel {
        AddCardViewModel(repository: repository)
    }

    /// An edit form for `card` on the same repository (edit and delete). Call ``refresh()`` after it closes.
    public func makeEditCardModel(for card: Card) -> AddCardViewModel {
        AddCardViewModel(repository: repository, editing: card)
    }

    /// The row's subtitle for `card`, e.g. `"Due on day 15"`.
    public nonisolated static func dueDayText(for card: Card) -> String {
        String(localized: "Due on day \(card.dueDay)", bundle: .module)
    }
}
