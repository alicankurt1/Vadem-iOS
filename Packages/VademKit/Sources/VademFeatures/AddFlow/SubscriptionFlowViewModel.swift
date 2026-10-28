import Foundation
import Observation
import VademCore

/// The steps of the subscription add flow (``SubscriptionFlowView``), in order.
public enum SubscriptionFlowStep: String, CaseIterable, Sendable, Identifiable {
    /// The ``AmountKeypad`` ("How much?").
    case amount
    /// Monthly / Yearly chips ("How often?").
    case period
    /// The ``CardPickerStep`` ("Which card?").
    case card
    /// Optional title: quick chips or Skip ("What is it?").
    case title
    /// Summary with the renewal day and the Save button.
    case summary

    public var id: String { rawValue }

    /// The launch argument that opens Home with the flow presented at this step (UI check):
    /// `-ui-add-subscription-flow-<step>`, e.g. `-ui-add-subscription-flow-summary`.
    public var launchArgument: String { "-ui-add-subscription-flow-\(rawValue)" }

    /// The step whose ``launchArgument`` is in `arguments` (the first in step order), or `nil`.
    public static func step(in arguments: [String]) -> SubscriptionFlowStep? {
        allCases.first { arguments.contains($0.launchArgument) }
    }
}

/// Drives the subscription add flow: one decision per step, then a summary with one Save button.
///
/// Wraps an ``AddSubscriptionViewModel`` (the existing form's model), so validation and the saved
/// ``SubscriptionItem`` are the same as the form's. The keypad writes the form's amount, the chips
/// its period, the card picker its card (``CardPicker/initialSelection(cards:lastUsedCardID:)``
/// preselected) and the title chips its title. An empty title is saved as ``defaultTitle``.
/// The renewal day and first month are the form's initial values (Home passes today's day).
@MainActor
@Observable
public final class SubscriptionFlowViewModel: Identifiable {
    /// The title saved when the user skips the title step: "Subscription".
    public nonisolated static var defaultTitle: String {
        String(localized: "Subscription", bundle: .module)
    }

    /// The quick title chips of the title step, in order.
    public nonisolated static var quickTitles: [String] {
        [
            String(localized: "Streaming", bundle: .module),
            String(localized: "Music", bundle: .module),
            String(localized: "Cloud storage", bundle: .module),
            String(localized: "Gym", bundle: .module),
            String(localized: "Phone line", bundle: .module),
            String(localized: "Internet", bundle: .module),
        ]
    }

    /// The form model the flow fills in and saves through.
    public let form: AddSubscriptionViewModel
    /// The ordered steps and the one showing.
    public private(set) var steps: FlowSteps<SubscriptionFlowStep>
    /// What the keypad typed; every change is written to the form's amount.
    public var keypad: AmountKeypadState {
        didSet { form.amountText = keypad.text }
    }
    /// The cards the picker shows: the form's cards plus any card added with "New card".
    public private(set) var cards: [Card]
    /// `true` while the summary shows the renewal day stepper (after "Change").
    public var isChangingRenewalDay = false

    @ObservationIgnored private let onSaved: (Card.ID?) -> Void

    /// Creates the flow at `start` around `form`.
    ///
    /// `lastUsedCardID` is preselected when it is one of the form's cards, otherwise "No card".
    /// `amount` starts the keypad with a value (UI check). `locale` must be the form's locale, so the
    /// keypad types the separator the form parses. `onSaved` gets the chosen card after a successful save.
    public init(
        form: AddSubscriptionViewModel,
        start: SubscriptionFlowStep = .amount,
        lastUsedCardID: Card.ID?,
        amount: Decimal? = nil,
        locale: Locale = .current,
        onSaved: @escaping (Card.ID?) -> Void = { _ in }
    ) {
        self.form = form
        self.steps = FlowSteps(SubscriptionFlowStep.allCases, startingAt: start)
        self.keypad = AmountKeypadState(amount: amount, locale: locale)
        self.cards = form.cards
        self.onSaved = onSaved
        // didSet init içinde çalışmaz; başlangıç tutarı forma elle yazılır.
        form.amountText = keypad.text
        form.cardID = CardPicker.initialSelection(cards: form.cards, lastUsedCardID: lastUsedCardID)
    }

    /// The step showing.
    public var step: SubscriptionFlowStep { steps.current }

    /// `true` when the amount step can continue (amount above zero).
    public var canContinueAmount: Bool { keypad.isPositive }

    /// Moves to the next step; on the amount step only when ``canContinueAmount``.
    public func advance() {
        if step == .amount, !canContinueAmount { return }
        steps.advance()
    }

    /// Moves to the previous step; returns `false` on the first step (the presenter leaves the flow).
    @discardableResult
    public func goBack() -> Bool {
        steps.goBack()
    }

    /// Stores `period` and advances.
    public func choose(period: Subscription.Period) {
        form.period = period
        advance()
    }

    /// Stores `cardID` (`nil` = "No card") and advances.
    public func choose(cardID: Card.ID?) {
        form.cardID = cardID
        advance()
    }

    /// Adds a card saved with "New card" to ``cards`` and selects it; the picker stays open.
    public func didAddCard(_ card: Card) {
        if !cards.contains(where: { $0.id == card.id }) {
            cards.append(card)
        }
        form.cardID = card.id
    }

    /// Stores `title` (a quick chip) and advances.
    public func choose(title: String) {
        form.title = title
        advance()
    }

    /// Clears the title (saved as ``defaultTitle``) and advances.
    public func skipTitle() {
        form.title = ""
        advance()
    }

    /// The title that will be saved: the chosen one, or ``defaultTitle`` when empty.
    public var effectiveTitle: String {
        let trimmed = form.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultTitle : trimmed
    }

    /// The chosen card's name, or "No card".
    public var cardTitle: String {
        cards.first { $0.id == form.cardID }?.name ?? String(localized: "No card", bundle: .module)
    }

    /// The form's draft with ``effectiveTitle`` as its title: what Save stores.
    public var draft: SubscriptionDraft {
        var draft = form.draft
        draft.title = effectiveTitle
        return draft
    }

    /// `true` when ``draft`` is valid, so Save can be enabled.
    public var canSave: Bool { draft.isValid }

    /// Saves through the form (empty title → ``defaultTitle``). Returns `true` on success and
    /// reports the chosen card to `onSaved`; a failure sets the form's ``AddSubscriptionViewModel/failureMessage``.
    @discardableResult
    public func save() -> Bool {
        form.title = effectiveTitle
        guard form.save() else { return false }
        onSaved(form.cardID)
        return true
    }
}
