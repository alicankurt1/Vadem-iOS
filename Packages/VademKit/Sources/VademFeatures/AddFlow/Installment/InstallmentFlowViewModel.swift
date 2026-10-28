import Foundation
import Observation
import VademCore

/// The steps of the quick installment flow, in order: one decision per step.
public enum InstallmentFlowStep: String, CaseIterable, Hashable, Sendable {
    /// The total, typed on the ``AmountKeypad``.
    case amount
    /// The number of installments: chips (``InstallmentFlowViewModel/countPresets``) or Other.
    case count
    /// The card: last used preselected, No card, or a new card.
    case card
    /// The first due month: This month, Next month or Other.
    case firstMonth
    /// An optional title: typed, a quick chip, or skipped.
    case title
    /// Everything chosen so far, the payment day ("Change") and the Save button.
    case summary
}

/// A choice of the count step: one of ``InstallmentFlowViewModel/countPresets`` or Other.
public enum InstallmentCountChoice: Hashable, Sendable {
    case preset(Int)
    case other
}

/// A choice of the first-month step.
public enum InstallmentMonthChoice: Hashable, Sendable {
    case thisMonth
    case nextMonth
    case other
}

/// Drives the quick installment flow (amount → count → card → first month → title → summary).
///
/// Validation and saving are the existing form's: the flow builds the same ``InstallmentDraft``
/// and saves through ``PaymentRepository``. An empty title becomes ``defaultTitle``.
/// The payment day is not a step: it starts at the chosen card's due day, or today's day without
/// a card, and can be changed on the summary (only without a card; with a card the card decides).
/// "Today" is injected (`todayMonth`, `todayDay`), never read from the clock.
/// After a successful ``save()`` the chosen card (or "No card") is remembered in the ``LastUsedCardStore``.
@MainActor
@Observable
public final class InstallmentFlowViewModel {
    /// The count chips, before "Other".
    public nonisolated static let countPresets = [3, 6, 9, 12, 18]
    /// The count "Other" starts at when no other count was chosen yet.
    public nonisolated static let otherCountStart = 24
    /// The title saved when the title step is skipped or left empty: "Installment" ("Taksit").
    public nonisolated static var defaultTitle: String {
        String(localized: "Installment", bundle: .module)
    }
    /// The quick title chips of the title step.
    public nonisolated static var quickTitles: [String] {
        [
            String(localized: "Phone", bundle: .module),
            String(localized: "Computer", bundle: .module),
            String(localized: "Appliance", bundle: .module),
            String(localized: "Furniture", bundle: .module),
        ]
    }

    /// The steps and which one is showing.
    public private(set) var steps = FlowSteps(InstallmentFlowStep.allCases)
    /// The amount keypad's state; ``AmountKeypadState/amount`` is the total.
    public var keypad: AmountKeypadState
    /// The chosen number of installments, or `nil` before the count step is decided.
    public private(set) var count: Int?
    /// `true` while the count step shows the "Other" stepper.
    public private(set) var isEnteringOtherCount = false
    /// The chosen card, or `nil` for "No card".
    public private(set) var cardID: Card.ID?
    /// The month of the first payment; starts at today's month.
    public private(set) var firstMonth: YearMonth
    /// The chip chosen on the first-month step, or `nil` before it is decided.
    public private(set) var monthChoice: InstallmentMonthChoice?
    /// The title as typed or chosen; may be empty (``resolvedTitle`` then is ``defaultTitle``).
    public var title: String = ""
    /// The payment day of a card-less installment; see ``changePaymentDay(to:)``.
    public private(set) var paymentDay: Int
    /// `true` after "Change" was tapped on the summary: the payment day stepper is showing.
    public private(set) var isChangingPaymentDay = false
    /// The cards to choose from, in the repository's order.
    public private(set) var cards: [Card] = []
    /// The months the "Other" month stepper offers, in order; contains today's month.
    public let firstMonthOptions: [YearMonth]
    /// A message for a load or save failure, or `nil`.
    public private(set) var failureMessage: String?

    @ObservationIgnored private let repository: any PaymentRepository
    @ObservationIgnored private let lastUsedCard: LastUsedCardStore
    @ObservationIgnored private let todayMonth: YearMonth
    @ObservationIgnored private let todayDay: Int
    // Kullanıcı ödeme gününü elle değiştirdiyse kart seçimi onu ezmez.
    @ObservationIgnored private var hasChangedPaymentDay = false

    /// Creates the flow at the amount step and loads the cards; the last used card is preselected
    /// (``CardPicker/initialSelection(cards:lastUsedCardID:)``).
    ///
    /// `todayMonth` and `todayDay` are "today" (This month, the default payment day);
    /// `locale` decides the keypad's decimal separator.
    public init(
        repository: any PaymentRepository,
        todayMonth: YearMonth,
        todayDay: Int,
        lastUsedCard: LastUsedCardStore,
        locale: Locale = .current
    ) {
        self.repository = repository
        self.lastUsedCard = lastUsedCard
        self.todayMonth = todayMonth
        self.todayDay = todayDay
        self.keypad = AmountKeypadState(locale: locale)
        self.firstMonth = todayMonth
        self.firstMonthOptions = MonthOptions.months(
            around: todayMonth,
            before: AddInstallmentViewModel.monthsBefore,
            after: AddInstallmentViewModel.monthsAfter
        )
        self.paymentDay = Self.clampedDay(todayDay)
        loadCards()
        cardID = CardPicker.initialSelection(cards: cards, lastUsedCardID: lastUsedCard.cardID)
        paymentDay = defaultPaymentDay(for: cardID)
    }

    private func loadCards() {
        do {
            cards = try repository.cards()
        } catch {
            failureMessage = AddInstallmentViewModel.cardsLoadErrorMessage
        }
    }

    // MARK: Adımlar

    /// The question shown as the header of `step`.
    public func title(of step: InstallmentFlowStep) -> String {
        switch step {
        case .amount: String(localized: "How much?", bundle: .module)
        case .count: String(localized: "How many installments?", bundle: .module)
        case .card: String(localized: "Which card?", bundle: .module)
        case .firstMonth: String(localized: "When is the first payment?", bundle: .module)
        case .title: String(localized: "What is it for?", bundle: .module)
        case .summary: String(localized: "Check and save", bundle: .module)
        }
    }

    /// `true` when the current step shows a Continue button: the amount and title steps,
    /// and the count and first-month steps while their "Other" stepper is showing.
    public var showsContinue: Bool {
        switch steps.current {
        case .amount, .title: true
        case .count: isEnteringOtherCount
        case .firstMonth: monthChoice == .other
        case .card, .summary: false
        }
    }

    /// `true` when Continue is enabled: an amount above zero on the amount step,
    /// a title of valid length (or empty) on the title step.
    public var canContinue: Bool {
        switch steps.current {
        case .amount: keypad.isPositive
        case .title: !isTitleTooLong
        case .count: count != nil
        case .firstMonth, .card, .summary: true
        }
    }

    /// Advances from a step with a Continue button (see ``showsContinue``); ignored while
    /// ``canContinue`` is `false` or the step has no Continue button.
    public func continueFromCurrentStep() {
        guard showsContinue, canContinue else { return }
        steps.advance()
    }

    /// Moves to the previous step; returns `false` on the first step (the caller leaves the flow).
    @discardableResult
    public func goBack() -> Bool {
        steps.goBack()
    }

    // MARK: Taksit sayısı

    /// The chip highlighted on the count step.
    public var countChoice: InstallmentCountChoice? {
        if isEnteringOtherCount { return .other }
        return count.map { .preset($0) }
    }

    /// Applies a count chip: a preset sets ``count`` and advances; Other shows the stepper
    /// (starting at ``otherCountStart`` unless a non-preset count was chosen) and stays.
    public func chooseCount(_ choice: InstallmentCountChoice) {
        switch choice {
        case .preset(let value):
            count = value
            isEnteringOtherCount = false
            steps.advance()
        case .other:
            isEnteringOtherCount = true
            if count.map({ Self.countPresets.contains($0) }) ?? true {
                count = Self.otherCountStart
            }
        }
    }

    /// Sets the count from the "Other" stepper, clamped to ``InstallmentPlan/supportedCounts``.
    public func setOtherCount(_ value: Int) {
        count = min(max(value, InstallmentPlan.supportedCounts.lowerBound), InstallmentPlan.supportedCounts.upperBound)
    }

    // MARK: Kart

    /// Chooses `id` (`nil`: No card) and advances. Unless the payment day was changed,
    /// it follows the card's due day (today's day without a card).
    public func chooseCard(_ id: Card.ID?) {
        cardID = id
        if !hasChangedPaymentDay { paymentDay = defaultPaymentDay(for: id) }
        steps.advance()
    }

    /// A new add-card form on the same repository; pass its saved card to ``selectAddedCard(_:)``.
    public func makeAddCardModel() -> AddCardViewModel {
        AddCardViewModel(repository: repository)
    }

    /// Reloads ``cards`` after `card` was saved by the add-card form, then chooses it (and advances).
    ///
    /// A load error sets ``failureMessage``; the card is chosen anyway, since it was saved.
    public func selectAddedCard(_ card: Card) {
        do {
            cards = try repository.cards()
            if failureMessage == AddInstallmentViewModel.cardsLoadErrorMessage { failureMessage = nil }
        } catch {
            failureMessage = AddInstallmentViewModel.cardsLoadErrorMessage
        }
        // Kart listesi yüklenemese de yeni kart seçilebilsin diye listeye eklenir.
        if !cards.contains(where: { $0.id == card.id }) { cards.append(card) }
        chooseCard(card.id)
    }

    /// The chosen card's name, or "No card".
    public var cardTitle: String {
        cards.first { $0.id == cardID }?.name ?? String(localized: "No card", bundle: .module)
    }

    // MARK: İlk ay

    /// Applies a month chip: This month and Next month set ``firstMonth`` (from today) and advance;
    /// Other shows the month stepper and stays.
    public func chooseMonth(_ choice: InstallmentMonthChoice) {
        monthChoice = choice
        switch choice {
        case .thisMonth:
            firstMonth = todayMonth
            steps.advance()
        case .nextMonth:
            firstMonth = todayMonth.adding(months: 1)
            steps.advance()
        case .other:
            break
        }
    }

    /// The index of ``firstMonth`` in ``firstMonthOptions`` (for the "Other" stepper).
    public var firstMonthIndex: Int {
        firstMonthOptions.firstIndex(of: firstMonth) ?? 0
    }

    /// Sets ``firstMonth`` to the option at `index`, clamped to ``firstMonthOptions``.
    public func setFirstMonthIndex(_ index: Int) {
        guard !firstMonthOptions.isEmpty else { return }
        firstMonth = firstMonthOptions[min(max(index, 0), firstMonthOptions.count - 1)]
    }

    /// The month as `"October 2026"`, like Home.
    public func title(of month: YearMonth) -> String {
        HomeViewModel.title(of: month)
    }

    // MARK: Başlık

    /// Uses `title` (a quick chip) and advances.
    public func chooseTitle(_ title: String) {
        self.title = title
        steps.advance()
    }

    /// Clears the title (``defaultTitle`` is saved) and advances.
    public func skipTitle() {
        title = ""
        steps.advance()
    }

    /// The title that is saved: the trimmed ``title``, or ``defaultTitle`` when it is empty.
    public var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultTitle : trimmed
    }

    /// `true` when the typed title is longer than ``InstallmentItem/maxTitleLength``.
    public var isTitleTooLong: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count > InstallmentItem.maxTitleLength
    }

    // MARK: Ödeme günü

    /// `true` when the payment day can be changed: only without a card (a card's due day decides).
    public var canChangePaymentDay: Bool { cardID == nil }

    /// The day shown on the summary: the card's due day, or ``paymentDay`` without a card.
    public var effectivePaymentDay: Int {
        cards.first { $0.id == cardID }.map { Self.clampedDay($0.dueDay) } ?? paymentDay
    }

    /// Shows the payment day stepper ("Change" on the summary); ignored with a card.
    public func beginChangingPaymentDay() {
        guard canChangePaymentDay else { return }
        isChangingPaymentDay = true
    }

    /// Sets ``paymentDay``, clamped to ``InstallmentItem/supportedPaymentDays``; a card choice no longer resets it.
    public func changePaymentDay(to day: Int) {
        paymentDay = Self.clampedDay(day)
        hasChangedPaymentDay = true
    }

    // MARK: Kaydetme

    /// The draft built from the choices, validated exactly like the add-installment form's.
    public var draft: InstallmentDraft {
        InstallmentDraft(
            title: resolvedTitle,
            cardID: cardID,
            paymentDay: paymentDay,
            total: keypad.amount,
            // Sayı seçilmeden taslak geçersiz kalır (0 desteklenen aralıkta değil).
            count: count ?? 0,
            firstMonth: firstMonth
        )
    }

    /// `true` when the draft is valid, so Save is enabled.
    public var canSave: Bool { draft.isValid }

    /// Saves the draft as a new installment and remembers the chosen card.
    ///
    /// Returns `true` on success; an invalid draft returns `false`, a repository error sets
    /// ``failureMessage`` and returns `false`.
    @discardableResult
    public func save() -> Bool {
        guard let item = draft.makeItem() else { return false }
        do {
            try repository.save(item)
            failureMessage = nil
            lastUsedCard.cardID = cardID
            return true
        } catch {
            failureMessage = AddInstallmentViewModel.saveErrorMessage
            return false
        }
    }

    // Kartın vade günü, kart yoksa bugünün günü; desteklenen aralığa kırpılır.
    private func defaultPaymentDay(for id: Card.ID?) -> Int {
        Self.clampedDay(cards.first { $0.id == id }?.dueDay ?? todayDay)
    }

    private nonisolated static func clampedDay(_ day: Int) -> Int {
        let days = InstallmentItem.supportedPaymentDays
        return min(max(day, days.lowerBound), days.upperBound)
    }
}
