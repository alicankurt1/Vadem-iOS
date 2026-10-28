import SwiftUI
import VademCore

/// The shared add-flow steps of the ``AddFlowGalleryView``, in order.
public enum AddFlowGalleryStep: String, CaseIterable, Sendable, Identifiable {
    /// The ``AmountKeypad`` step ("How much?").
    case keypad
    /// The ``ChoiceChips`` step ("How often?"); choosing a chip advances.
    case chips
    /// The ``CardPickerStep`` ("Which card?").
    case cardPicker

    public var id: String { rawValue }

    /// The launch argument that opens Home with the gallery presented at this step (UI check):
    /// `-ui-add-flow-keypad`, `-ui-add-flow-chips`, `-ui-add-flow-card`.
    public var launchArgument: String {
        switch self {
        case .keypad: "-ui-add-flow-keypad"
        case .chips: "-ui-add-flow-chips"
        case .cardPicker: "-ui-add-flow-card"
        }
    }

    /// The step whose ``launchArgument`` is in `arguments` (the first in step order), or `nil`.
    public static func step(in arguments: [String]) -> AddFlowGalleryStep? {
        allCases.first { arguments.contains($0.launchArgument) }
    }
}

/// A sample flow made of the shared steps (amount keypad → chips → card picker) inside a
/// ``FlowStepContainer``, so the UI check can capture each shared step screen with real data.
///
/// Continue on the keypad needs an amount above zero; choosing a chip advances on its own;
/// choosing a card only checks it (last step). "New card" opens the add-card form and selects
/// the saved card. Nothing is saved by the flow itself.
@MainActor
public struct AddFlowGalleryView: View {
    // Örnek sıklık seçenekleri; yalnızca çip adımını göstermek için.
    private enum Period: Hashable {
        case monthly
        case yearly
    }

    @State private var steps: FlowSteps<AddFlowGalleryStep>
    @State private var keypad: AmountKeypadState
    @State private var period: Period?
    @State private var cards: [Card]
    @State private var cardID: Card.ID?
    // "Yeni kart" ile açılan kart formunun modeli; nil iken sayfa kapalı.
    @State private var addCardModel: AddCardViewModel?
    private let makeAddCardModel: () -> AddCardViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates the flow at `start` with `cards` to pick from; `lastUsedCardID` is preselected
    /// (``CardPicker/initialSelection(cards:lastUsedCardID:)``), `locale` sets the keypad's separator.
    public init(
        start: AddFlowGalleryStep = .keypad,
        cards: [Card],
        lastUsedCardID: Card.ID?,
        locale: Locale = .current,
        makeAddCardModel: @escaping () -> AddCardViewModel
    ) {
        _steps = State(initialValue: FlowSteps(AddFlowGalleryStep.allCases, startingAt: start))
        _keypad = State(initialValue: AmountKeypadState(locale: locale))
        _cards = State(initialValue: cards)
        _cardID = State(initialValue: CardPicker.initialSelection(cards: cards, lastUsedCardID: lastUsedCardID))
        self.makeAddCardModel = makeAddCardModel
    }

    public var body: some View {
        FlowStepContainer(
            title: title(of: steps.current),
            stepNumber: steps.number,
            stepCount: steps.count,
            onBack: steps.isFirst ? nil : { move { steps.goBack() } },
            onClose: { dismiss() },
            canContinue: keypad.isPositive,
            onContinue: steps.current == .keypad ? { move { steps.advance() } } : nil
        ) {
            switch steps.current {
            case .keypad:
                AmountKeypad(state: $keypad)
            case .chips:
                ChoiceChips(
                    options: [
                        .init(value: Period.monthly, title: String(localized: "Monthly", bundle: .module)),
                        .init(value: Period.yearly, title: String(localized: "Yearly", bundle: .module)),
                    ],
                    selection: period, identifierPrefix: "flow.period"
                ) { value in
                    period = value
                    // Tek karar: çip seçilince bir sonraki adıma geçilir.
                    move { steps.advance() }
                }
            case .cardPicker:
                CardPickerStep(cards: cards, selection: cardID) { id in
                    cardID = id
                    move { steps.advance() }
                } onAddCard: {
                    addCardModel = makeAddCardModel()
                }
            }
        }
        .sheet(item: $addCardModel) { addCardModel in
            AddCardView(model: addCardModel) { card in
                // Yeni kart listeye eklenir ve seçilir.
                cards.append(card)
                cardID = card.id
            }
        }
    }

    // Adım geçişi; Reduce Motion veya -ui-static-motion açıkken animasyonsuz.
    private func move(_ change: () -> Void) {
        withAnimation(Motion.animation(Motion.quick, reduceMotion: reduceMotion)) {
            change()
        }
    }

    private func title(of step: AddFlowGalleryStep) -> String {
        switch step {
        case .keypad: String(localized: "How much?", bundle: .module)
        case .chips: String(localized: "How often?", bundle: .module)
        case .cardPicker: String(localized: "Which card?", bundle: .module)
        }
    }
}

#if DEBUG
#Preview {
    let model = HomeSampleData.makeViewModel()
    return AddFlowGalleryView(cards: model.pickerCards(), lastUsedCardID: nil, makeAddCardModel: model.makeAddCardModel)
}
#endif
