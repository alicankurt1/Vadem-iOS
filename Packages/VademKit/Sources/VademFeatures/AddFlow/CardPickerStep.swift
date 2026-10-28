import SwiftUI
import VademCore

/// Rules of the card picker step that do not need a view.
public enum CardPicker {
    /// The card to preselect: `lastUsedCardID` when it is still one of `cards`, otherwise `nil`
    /// ("No card"). The caller remembers the last used card; nothing is stored here.
    public static func initialSelection(cards: [Card], lastUsedCardID: Card.ID?) -> Card.ID? {
        guard let lastUsedCardID, cards.contains(where: { $0.id == lastUsedCardID }) else { return nil }
        return lastUsedCardID
    }
}

/// The card picker step: one row per card, a "No card" row that is always visible and
/// a "New card" row. Tapping a card or "No card" calls `onChoose` (the flow then advances).
///
/// The selected row shows a checkmark and has the selected trait. Rows are plain wrapping text,
/// at least 44 pt tall. Identifiers: `cardPicker.card.<index>` (from 0), `cardPicker.noCard`,
/// `cardPicker.newCard`.
@MainActor
public struct CardPickerStep: View {
    private let cards: [Card]
    private let selection: Card.ID?
    private let onChoose: (Card.ID?) -> Void
    private let onAddCard: () -> Void

    /// Creates the step for `cards` with `selection` checked (`nil` checks "No card");
    /// see ``CardPicker/initialSelection(cards:lastUsedCardID:)`` for the first value.
    public init(
        cards: [Card], selection: Card.ID?, onChoose: @escaping (Card.ID?) -> Void, onAddCard: @escaping () -> Void
    ) {
        self.cards = cards
        self.selection = selection
        self.onChoose = onChoose
        self.onAddCard = onAddCard
    }

    public var body: some View {
        VStack(spacing: 16) {
            SurfaceCard(rowVerticalPadding: 4) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    row(title: card.name, isSelected: selection == card.id, identifier: "cardPicker.card.\(index)") {
                        onChoose(card.id)
                    }
                }
                row(title: String(localized: "No card", bundle: .module), isSelected: selection == nil, identifier: "cardPicker.noCard") {
                    onChoose(nil)
                }
            }
            SurfaceCard(rowVerticalPadding: 4) {
                newCardRow
            }
        }
    }

    private func row(title: String, isSelected: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color.vademTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.vademBrand)
                        .accessibilityHidden(true)
                }
            }
            // En az 44 pt dokunma alanı.
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    // Ekleme satırı bağlantı gibi marka renginde; simge gizli, metin sarılır.
    private var newCardRow: some View {
        Button(action: onAddCard) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .accessibilityHidden(true)
                Text("New card", bundle: .module)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Color.vademBrand)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cardPicker.newCard")
    }
}
