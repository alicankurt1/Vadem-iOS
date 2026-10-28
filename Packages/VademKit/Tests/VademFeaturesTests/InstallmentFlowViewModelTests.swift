import Foundation
import Testing
import VademCore
import VademFeatures
import VademTestSupport

@MainActor
@Suite("InstallmentFlowViewModel")
struct InstallmentFlowViewModelTests {
    private static let october = YearMonth(year: 2026, month: 10)!
    private static let english = Locale(identifier: "en_US")

    private struct SaveFailingRepository: PaymentRepository {
        struct Failure: Error {}
        func cards() throws -> [Card] { [] }
        func save(_ card: Card) throws {}
        func deleteCard(id: Card.ID) throws {}
        func installments() throws -> [InstallmentItem] { [] }
        func save(_ item: InstallmentItem) throws { throw Failure() }
        func deleteInstallment(id: InstallmentItem.ID) throws {}
        func subscriptions() throws -> [SubscriptionItem] { [] }
        func save(_ item: SubscriptionItem) throws {}
        func deleteSubscription(id: SubscriptionItem.ID) throws {}
        func oneTimePayments() throws -> [OneTimePaymentItem] { [] }
        func save(_ item: OneTimePaymentItem) throws {}
        func deleteOneTimePayment(id: OneTimePaymentItem.ID) throws {}
    }

    private static func store() -> LastUsedCardStore {
        // Her test kendi temiz UserDefaults paketini kullanır.
        let name = "vadem.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return LastUsedCardStore(defaults: defaults)
    }

    private static func card(_ name: String, dueDay: Int) -> Card {
        Card(id: UUID(), name: name, statementDay: 5, dueDay: dueDay)!
    }

    private static func makeModel(
        cards: [Card] = [],
        lastUsed: Card.ID? = nil,
        todayDay: Int = 17,
        repository: InMemoryPaymentRepository = InMemoryPaymentRepository()
    ) throws -> (InstallmentFlowViewModel, InMemoryPaymentRepository, LastUsedCardStore) {
        for card in cards { try repository.save(card) }
        let lastUsedStore = store()
        lastUsedStore.cardID = lastUsed
        let model = InstallmentFlowViewModel(
            repository: repository, todayMonth: october, todayDay: todayDay,
            lastUsedCard: lastUsedStore, locale: english
        )
        return (model, repository, lastUsedStore)
    }

    private static func type(_ text: String, into model: InstallmentFlowViewModel) {
        for character in text {
            if let digit = character.wholeNumberValue {
                model.keypad.press(.digit(digit))
            } else {
                model.keypad.press(.decimalSeparator)
            }
        }
    }

    /// Tutarı yazıp tüm adımları kısa yoldan geçirir; özet adımında bırakır.
    private static func reachSummary(
        _ model: InstallmentFlowViewModel, amount: String = "1200", count: Int = 6, card: Card.ID? = nil
    ) {
        type(amount, into: model)
        model.continueFromCurrentStep()
        model.chooseCount(.preset(count))
        model.chooseCard(card)
        model.chooseMonth(.thisMonth)
        model.skipTitle()
    }

    // MARK: Adım sırası ve varsayılanlar

    @Test("Steps run amount, count, card, first month, title, summary")
    func stepOrder() throws {
        let (model, _, _) = try Self.makeModel()
        #expect(model.steps.steps == [.amount, .count, .card, .firstMonth, .title, .summary])
        #expect(model.steps.current == .amount)
        #expect(model.steps.count == 6)
    }

    @Test("Chips and Continue move through the steps in order")
    func advancing() throws {
        let (model, _, _) = try Self.makeModel()
        Self.type("500", into: model)
        model.continueFromCurrentStep()
        #expect(model.steps.current == .count)
        model.chooseCount(.preset(9))
        #expect(model.steps.current == .card)
        model.chooseCard(nil)
        #expect(model.steps.current == .firstMonth)
        model.chooseMonth(.nextMonth)
        #expect(model.steps.current == .title)
        model.continueFromCurrentStep()
        #expect(model.steps.current == .summary)
    }

    @Test("Count chips are 3, 6, 9, 12, 18")
    func countPresets() {
        #expect(InstallmentFlowViewModel.countPresets == [3, 6, 9, 12, 18])
    }

    @Test("Fresh flow has no count, no month choice, an empty title and no failure")
    func defaults() throws {
        let (model, _, _) = try Self.makeModel()
        #expect(model.count == nil)
        #expect(model.monthChoice == nil)
        #expect(model.title.isEmpty)
        #expect(model.firstMonth == Self.october)
        #expect(model.failureMessage == nil)
        #expect(!model.canSave)
    }

    // MARK: Tutar

    @Test("Continue on the amount step needs an amount above zero")
    func amountContinue() throws {
        let (model, _, _) = try Self.makeModel()
        #expect(model.showsContinue)
        #expect(!model.canContinue)
        model.continueFromCurrentStep()
        #expect(model.steps.current == .amount)
        Self.type("0", into: model)
        #expect(!model.canContinue)
        model.keypad.press(.delete)
        Self.type("1", into: model)
        #expect(model.canContinue)
        model.continueFromCurrentStep()
        #expect(model.steps.current == .count)
    }

    // MARK: Taksit sayısı

    @Test("Each count chip sets the count and advances", arguments: [3, 6, 9, 12, 18])
    func presetCount(value: Int) throws {
        let (model, _, _) = try Self.makeModel()
        Self.type("100", into: model)
        model.continueFromCurrentStep()
        model.chooseCount(.preset(value))
        #expect(model.count == value)
        #expect(model.countChoice == .preset(value))
        #expect(model.steps.current == .card)
    }

    @Test("Other shows the stepper and stays on the count step; Continue then advances")
    func otherCount() throws {
        let (model, _, _) = try Self.makeModel()
        Self.type("100", into: model)
        model.continueFromCurrentStep()
        #expect(!model.showsContinue)
        model.chooseCount(.other)
        #expect(model.steps.current == .count)
        #expect(model.isEnteringOtherCount)
        #expect(model.countChoice == .other)
        #expect(model.showsContinue)
        #expect(model.count != nil)
        model.setOtherCount(24)
        model.continueFromCurrentStep()
        #expect(model.steps.current == .card)
        #expect(model.count == 24)
    }

    @Test("Other count is clamped to 1...36", arguments: [(-5, 1), (0, 1), (1, 1), (36, 36), (37, 36), (1000, 36)])
    func otherCountClamped(input: Int, expected: Int) throws {
        let (model, _, _) = try Self.makeModel()
        model.chooseCount(.other)
        model.setOtherCount(input)
        #expect(model.count == expected)
    }

    // MARK: Kart

    @Test("No last used card preselects No card")
    func noLastUsed() throws {
        let (model, _, _) = try Self.makeModel(cards: [Self.card("Bonus", dueDay: 15)])
        #expect(model.cardID == nil)
        #expect(model.cardTitle.isEmpty == false)
    }

    @Test("Last used card is preselected")
    func lastUsedPreselected() throws {
        let first = Self.card("Bonus", dueDay: 15)
        let second = Self.card("World", dueDay: 22)
        let (model, _, _) = try Self.makeModel(cards: [first, second], lastUsed: second.id)
        #expect(model.cardID == second.id)
        #expect(model.cardTitle == "World")
        #expect(model.cards.count == 2)
    }

    @Test("A deleted last used card falls back to No card")
    func lastUsedDeleted() throws {
        let (model, _, _) = try Self.makeModel(cards: [Self.card("Bonus", dueDay: 15)], lastUsed: UUID())
        #expect(model.cardID == nil)
    }

    @Test("Choosing a card advances to the first month step")
    func chooseCardAdvances() throws {
        let card = Self.card("Bonus", dueDay: 15)
        let (model, _, _) = try Self.makeModel(cards: [card])
        Self.type("100", into: model)
        model.continueFromCurrentStep()
        model.chooseCount(.preset(3))
        model.chooseCard(card.id)
        #expect(model.cardID == card.id)
        #expect(model.steps.current == .firstMonth)
    }

    @Test("A card saved by the add-card form is selected and listed")
    func selectAddedCard() throws {
        let (model, repository, _) = try Self.makeModel()
        let added = Self.card("Fresh", dueDay: 9)
        try repository.save(added)
        Self.type("100", into: model)
        model.continueFromCurrentStep()
        model.chooseCount(.preset(3))
        model.selectAddedCard(added)
        #expect(model.cards.contains { $0.id == added.id })
        #expect(model.cardID == added.id)
        #expect(model.steps.current == .firstMonth)
    }

    // MARK: İlk ay

    @Test("This month and Next month set the first month from today and advance")
    func monthChips() throws {
        let (model, _, _) = try Self.makeModel()
        model.chooseMonth(.nextMonth)
        #expect(model.firstMonth == YearMonth(year: 2026, month: 11)!)
        model.chooseMonth(.thisMonth)
        #expect(model.firstMonth == Self.october)
    }

    @Test("Next month rolls over the year end")
    func nextMonthYearEnd() throws {
        let december = YearMonth(year: 2026, month: 12)!
        let model = InstallmentFlowViewModel(
            repository: InMemoryPaymentRepository(), todayMonth: december, todayDay: 5,
            lastUsedCard: Self.store(), locale: Self.english
        )
        model.chooseMonth(.nextMonth)
        #expect(model.firstMonth == YearMonth(year: 2027, month: 1)!)
    }

    @Test("Other month shows the stepper and stays until Continue")
    func otherMonth() throws {
        let (model, _, _) = try Self.makeModel()
        Self.type("100", into: model)
        model.continueFromCurrentStep()
        model.chooseCount(.preset(3))
        model.chooseCard(nil)
        model.chooseMonth(.other)
        #expect(model.steps.current == .firstMonth)
        #expect(model.showsContinue)
        model.setFirstMonthIndex(model.firstMonthIndex + 2)
        #expect(model.firstMonth == YearMonth(year: 2026, month: 12)!)
        model.continueFromCurrentStep()
        #expect(model.steps.current == .title)
    }

    @Test("Month stepper index is clamped to the options")
    func monthIndexClamped() throws {
        let (model, _, _) = try Self.makeModel()
        model.setFirstMonthIndex(-3)
        #expect(model.firstMonth == model.firstMonthOptions.first)
        model.setFirstMonthIndex(10_000)
        #expect(model.firstMonth == model.firstMonthOptions.last)
        #expect(model.firstMonthOptions.contains(Self.october))
    }

    // MARK: Başlık

    @Test("Empty and blank titles resolve to the default title", arguments: ["", "   ", "\n"])
    func defaultTitle(title: String) throws {
        let (model, _, _) = try Self.makeModel()
        model.title = title
        #expect(model.resolvedTitle == InstallmentFlowViewModel.defaultTitle)
        #expect(!InstallmentFlowViewModel.defaultTitle.isEmpty)
    }

    @Test("A typed title is trimmed")
    func typedTitleTrimmed() throws {
        let (model, _, _) = try Self.makeModel()
        model.title = "  Laptop "
        #expect(model.resolvedTitle == "Laptop")
    }

    @Test("A title of 61 characters is too long and blocks Continue; 60 is fine")
    func titleLength() throws {
        let (model, _, _) = try Self.makeModel()
        Self.type("100", into: model)
        model.continueFromCurrentStep()
        model.chooseCount(.preset(3))
        model.chooseCard(nil)
        model.chooseMonth(.thisMonth)
        #expect(model.steps.current == .title)
        model.title = String(repeating: "a", count: 60)
        #expect(!model.isTitleTooLong)
        #expect(model.canContinue)
        model.title = String(repeating: "a", count: 61)
        #expect(model.isTitleTooLong)
        #expect(!model.canContinue)
        model.continueFromCurrentStep()
        #expect(model.steps.current == .title)
    }

    @Test("Quick title chip sets the title and advances; Skip clears it and advances")
    func titleChipAndSkip() throws {
        let (model, _, _) = try Self.makeModel()
        #expect(!InstallmentFlowViewModel.quickTitles.isEmpty)
        let quick = try #require(InstallmentFlowViewModel.quickTitles.first)
        Self.type("100", into: model)
        model.continueFromCurrentStep()
        model.chooseCount(.preset(3))
        model.chooseCard(nil)
        model.chooseMonth(.thisMonth)
        model.chooseTitle(quick)
        #expect(model.title == quick)
        #expect(model.steps.current == .summary)

        let (other, _, _) = try Self.makeModel()
        Self.reachSummary(other)
        #expect(other.title.isEmpty)
        #expect(other.steps.current == .summary)
        #expect(other.resolvedTitle == InstallmentFlowViewModel.defaultTitle)
    }

    // MARK: Ödeme günü

    @Test("Without a card the payment day defaults to today's day", arguments: [1, 17, 28, 31])
    func paymentDayFromToday(today: Int) throws {
        let (model, _, _) = try Self.makeModel(todayDay: today)
        #expect(model.effectivePaymentDay == min(today, InstallmentItem.supportedPaymentDays.upperBound))
        #expect(model.canChangePaymentDay)
    }

    @Test("With a card the payment day is the card's due day and cannot be changed")
    func paymentDayFromCard() throws {
        let card = Self.card("Bonus", dueDay: 22)
        let (model, _, _) = try Self.makeModel(cards: [card], lastUsed: card.id, todayDay: 3)
        #expect(model.effectivePaymentDay == 22)
        #expect(!model.canChangePaymentDay)
        model.beginChangingPaymentDay()
        #expect(!model.isChangingPaymentDay)
    }

    @Test("Choosing a card moves the payment day to its due day; No card goes back to today")
    func paymentDayFollowsCard() throws {
        let card = Self.card("Bonus", dueDay: 22)
        let (model, _, _) = try Self.makeModel(cards: [card], todayDay: 3)
        model.chooseCard(card.id)
        #expect(model.effectivePaymentDay == 22)
        model.chooseCard(nil)
        #expect(model.effectivePaymentDay == 3)
    }

    @Test("Change shows the stepper; the new day is kept and clamped")
    func changePaymentDay() throws {
        let (model, _, _) = try Self.makeModel(todayDay: 17)
        #expect(!model.isChangingPaymentDay)
        model.beginChangingPaymentDay()
        #expect(model.isChangingPaymentDay)
        model.changePaymentDay(to: 5)
        #expect(model.paymentDay == 5)
        #expect(model.effectivePaymentDay == 5)
        model.changePaymentDay(to: 0)
        #expect(model.paymentDay == InstallmentItem.supportedPaymentDays.lowerBound)
        model.changePaymentDay(to: 99)
        #expect(model.paymentDay == InstallmentItem.supportedPaymentDays.upperBound)
    }

    // MARK: Kaydetme

    @Test("Saving without a card stores amount, count, first month, day and default title")
    func saveCardless() throws {
        let (model, repository, _) = try Self.makeModel(todayDay: 17)
        Self.reachSummary(model, amount: "1200", count: 6, card: nil)
        #expect(model.canSave)
        #expect(model.save())
        let item = try #require(repository.installments().first)
        #expect(try repository.installments().count == 1)
        #expect(item.title == InstallmentFlowViewModel.defaultTitle)
        #expect(item.cardID == nil)
        #expect(item.paymentDay == 17)
        #expect(item.plan.total == Money(1200))
        #expect(item.plan.count == 6)
        #expect(item.plan.firstMonth == Self.october)
    }

    @Test("Saving with a card stores the card and no own payment day")
    func saveWithCard() throws {
        let card = Self.card("Bonus", dueDay: 22)
        let (model, repository, _) = try Self.makeModel(cards: [card], lastUsed: card.id)
        Self.type("900", into: model)
        model.continueFromCurrentStep()
        model.chooseCount(.preset(3))
        model.chooseCard(card.id)
        model.chooseMonth(.nextMonth)
        model.chooseTitle("Phone")
        #expect(model.save())
        let item = try #require(repository.installments().first)
        #expect(item.cardID == card.id)
        #expect(item.paymentDay == nil)
        #expect(item.title == "Phone")
        #expect(item.plan.firstMonth == YearMonth(year: 2026, month: 11)!)
        #expect(item.plan.count == 3)
    }

    @Test("A changed payment day is saved for a card-less installment")
    func saveChangedDay() throws {
        let (model, repository, _) = try Self.makeModel(todayDay: 17)
        Self.reachSummary(model)
        model.beginChangingPaymentDay()
        model.changePaymentDay(to: 3)
        #expect(model.save())
        #expect(try repository.installments().first?.paymentDay == 3)
    }

    @Test("A decimal amount is kept exactly")
    func saveDecimalAmount() throws {
        let (model, repository, _) = try Self.makeModel()
        Self.reachSummary(model, amount: "1234.56")
        #expect(model.save())
        #expect(try repository.installments().first?.plan.total == Money(Decimal(string: "1234.56")!))
    }

    @Test("Flow validity equals InstallmentDraft validity")
    func sameValidationAsDraft() throws {
        let (model, _, _) = try Self.makeModel()
        #expect(model.canSave == model.draft.isValid)
        Self.reachSummary(model)
        #expect(model.canSave == model.draft.isValid)
        #expect(model.canSave)
        model.title = String(repeating: "x", count: 61)
        #expect(model.canSave == model.draft.isValid)
    }

    @Test("Saving before any count was chosen is refused and stores nothing")
    func invalidSave() throws {
        let (model, repository, _) = try Self.makeModel()
        Self.type("100", into: model)
        #expect(!model.canSave)
        #expect(!model.save())
        #expect(try repository.installments().isEmpty)
    }

    @Test("Saving remembers the chosen card; saving without a card clears it")
    func rememberCard() throws {
        let card = Self.card("Bonus", dueDay: 22)
        let (model, _, store) = try Self.makeModel(cards: [card])
        Self.reachSummary(model, card: card.id)
        #expect(model.save())
        #expect(store.cardID == card.id)

        let (second, _, secondStore) = try Self.makeModel(cards: [card], lastUsed: card.id)
        Self.reachSummary(second, card: nil)
        #expect(second.save())
        #expect(secondStore.cardID == nil)
    }

    @Test("A failed save reports a message and does not remember the card")
    func saveFailure() throws {
        let store = Self.store()
        let model = InstallmentFlowViewModel(
            repository: SaveFailingRepository(), todayMonth: Self.october, todayDay: 5,
            lastUsedCard: store, locale: Self.english
        )
        Self.reachSummary(model)
        #expect(!model.save())
        #expect(model.failureMessage != nil)
        #expect(store.cardID == nil)
    }

    @Test("Back moves one step; on the first step it returns false")
    func goBack() throws {
        let (model, _, _) = try Self.makeModel()
        #expect(!model.goBack())
        Self.type("100", into: model)
        model.continueFromCurrentStep()
        #expect(model.steps.current == .count)
        #expect(model.goBack())
        #expect(model.steps.current == .amount)
        #expect(model.keypad.amount == 100)
    }

    @Test("Every step has a non-empty question")
    func stepTitles() throws {
        let (model, _, _) = try Self.makeModel()
        for step in InstallmentFlowStep.allCases {
            #expect(!model.title(of: step).isEmpty)
        }
        #expect(Set(InstallmentFlowStep.allCases.map { model.title(of: $0) }).count == 6)
    }
}

@MainActor
@Suite("LastUsedCardStore")
struct LastUsedCardStoreTests {
    private static func defaults() -> UserDefaults {
        let name = "vadem.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Starts empty")
    func empty() {
        #expect(LastUsedCardStore(defaults: Self.defaults()).cardID == nil)
    }

    @Test("Remembers a card id across store instances on the same defaults")
    func roundTrip() {
        let defaults = Self.defaults()
        let id = UUID()
        LastUsedCardStore(defaults: defaults).cardID = id
        #expect(LastUsedCardStore(defaults: defaults).cardID == id)
    }

    @Test("Setting nil clears the remembered card")
    func clear() {
        let defaults = Self.defaults()
        let store = LastUsedCardStore(defaults: defaults)
        store.cardID = UUID()
        store.cardID = nil
        #expect(store.cardID == nil)
        #expect(defaults.object(forKey: LastUsedCardStore.key) == nil)
    }

    @Test("A value that is not a UUID reads as no card")
    func garbage() {
        let defaults = Self.defaults()
        defaults.set("not-a-uuid", forKey: LastUsedCardStore.key)
        #expect(LastUsedCardStore(defaults: defaults).cardID == nil)
    }
}
