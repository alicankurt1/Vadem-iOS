import Foundation
import Testing
import VademCore
import VademFeatures
import VademTestSupport

@MainActor
@Suite("CardListViewModel")
struct CardListViewModelTests {
    // Her çağrıda hata fırlatan depo: yükleme hatası durumunu sınar.
    private struct FailingRepository: PaymentRepository {
        struct Failure: Error {}
        func cards() throws -> [Card] { throw Failure() }
        func save(_ card: Card) throws { throw Failure() }
        func deleteCard(id: Card.ID) throws { throw Failure() }
        func installments() throws -> [InstallmentItem] { throw Failure() }
        func save(_ item: InstallmentItem) throws { throw Failure() }
        func deleteInstallment(id: InstallmentItem.ID) throws { throw Failure() }
        func subscriptions() throws -> [SubscriptionItem] { throw Failure() }
        func save(_ item: SubscriptionItem) throws { throw Failure() }
        func deleteSubscription(id: SubscriptionItem.ID) throws { throw Failure() }
    }

    // Yalnızca ilk çağrıda başarılı olan, sonra hata veren depo: eski listenin temizlendiğini sınar.
    private final class FlakyRepository: PaymentRepository {
        struct Failure: Error {}
        let inner = InMemoryPaymentRepository()
        var fails = false
        func cards() throws -> [Card] { if fails { throw Failure() }; return try inner.cards() }
        func save(_ card: Card) throws { try inner.save(card) }
        func deleteCard(id: Card.ID) throws { try inner.deleteCard(id: id) }
        func installments() throws -> [InstallmentItem] { try inner.installments() }
        func save(_ item: InstallmentItem) throws { try inner.save(item) }
        func deleteInstallment(id: InstallmentItem.ID) throws { try inner.deleteInstallment(id: id) }
        func subscriptions() throws -> [SubscriptionItem] { try inner.subscriptions() }
        func save(_ item: SubscriptionItem) throws { try inner.save(item) }
        func deleteSubscription(id: SubscriptionItem.ID) throws { try inner.deleteSubscription(id: id) }
    }

    @Test("Empty repository shows the empty state")
    func emptyState() {
        let model = CardListViewModel(repository: InMemoryPaymentRepository())
        #expect(model.cards.isEmpty)
        #expect(model.state == .empty)
        #expect(model.isEmpty)
    }

    @Test("Loads saved cards on init, sorted by name")
    func loadsOnInit() throws {
        let repository = InMemoryPaymentRepository()
        try repository.save(Fixture.card("Zeta"))
        try repository.save(Fixture.card("alpha"))
        try repository.save(Fixture.card("Mid"))
        let model = CardListViewModel(repository: repository)
        #expect(model.cards.map(\.name) == ["alpha", "Mid", "Zeta"])
        #expect(model.state == .loaded)
        #expect(!model.isEmpty)
    }

    @Test("Refresh shows a card saved after init")
    func refreshAfterSave() throws {
        let repository = InMemoryPaymentRepository()
        let model = CardListViewModel(repository: repository)
        #expect(model.isEmpty)
        try repository.save(Fixture.card("Bonus"))
        #expect(model.isEmpty, "list must not change before refresh")
        model.refresh()
        #expect(model.cards.map(\.name) == ["Bonus"])
        #expect(model.state == .loaded)
    }

    @Test("Refresh returns to the empty state after the last card is deleted")
    func refreshAfterDelete() throws {
        let repository = InMemoryPaymentRepository()
        let card = try Fixture.card("Bonus")
        try repository.save(card)
        let model = CardListViewModel(repository: repository)
        #expect(model.state == .loaded)
        try repository.deleteCard(id: card.id)
        model.refresh()
        #expect(model.cards.isEmpty)
        #expect(model.state == .empty)
    }

    @Test("Refresh shows an edited card name")
    func refreshAfterEdit() throws {
        let repository = InMemoryPaymentRepository()
        let card = try Fixture.card("Bonus")
        try repository.save(card)
        let model = CardListViewModel(repository: repository)
        let renamed = try #require(Card(id: card.id, name: "Renamed", statementDay: card.statementDay, dueDay: card.dueDay))
        try repository.save(renamed)
        model.refresh()
        #expect(model.cards.map(\.name) == ["Renamed"])
    }

    @Test("Repository failure gives the error state and no stale cards")
    func failureState() {
        let model = CardListViewModel(repository: FailingRepository())
        #expect(model.cards.isEmpty)
        #expect(model.state == .error(message: CardListViewModel.loadErrorMessage))
        #expect(!model.isEmpty, "an error is not the empty state")
    }

    @Test("A failing refresh clears the previously loaded cards")
    func failingRefreshClearsList() throws {
        let repository = FlakyRepository()
        try repository.save(Fixture.card("Bonus"))
        let model = CardListViewModel(repository: repository)
        #expect(model.state == .loaded)
        repository.fails = true
        model.refresh()
        #expect(model.cards.isEmpty)
        #expect(model.state == .error(message: CardListViewModel.loadErrorMessage))
        repository.fails = false
        model.refresh()
        #expect(model.state == .loaded)
    }

    @Test("Add form model starts empty and saves into the same repository")
    func addModelSharesRepository() throws {
        let repository = InMemoryPaymentRepository()
        let list = CardListViewModel(repository: repository)
        let form = list.makeAddCardModel()
        #expect(!form.isEditing)
        form.name = "Bonus"
        form.statementDayText = "10"
        form.dueDayText = "20"
        #expect(form.canSave)
        _ = form.save()
        list.refresh()
        #expect(list.cards.map(\.name) == ["Bonus"])
    }

    @Test("Edit form model is prefilled and can delete an unused card")
    func editModelDeletes() throws {
        let repository = InMemoryPaymentRepository()
        let card = try #require(Card(name: "Bonus", statementDay: 10, dueDay: 20))
        try repository.save(card)
        let list = CardListViewModel(repository: repository)
        let form = list.makeEditCardModel(for: card)
        #expect(form.isEditing)
        #expect(form.name == "Bonus")
        #expect(form.statementDayText == "10")
        #expect(form.dueDayText == "20")
        _ = form.delete()
        list.refresh()
        #expect(list.isEmpty)
    }

    @Test("Due day subtitle names the day", arguments: [1, 15, 31])
    func dueDayText(day: Int) throws {
        let card = try #require(Card(name: "Bonus", statementDay: 1, dueDay: day))
        #expect(CardListViewModel.dueDayText(for: card).contains("\(day)"))
    }
}

@MainActor
@Suite("SettingsViewModel Cards row")
struct SettingsCardsRowTests {
    @Test("Cards row is hidden without a repository")
    func hiddenWithoutRepository() {
        let model = SettingsViewModel(dependencies: .inMemory())
        #expect(!model.showsCards)
        #expect(model.makeCardListModel() == nil)
    }

    @Test("Cards row is shown with a repository and builds a model on it")
    func shownWithRepository() throws {
        let repository = InMemoryPaymentRepository()
        try repository.save(Fixture.card("Bonus"))
        let model = SettingsViewModel(dependencies: .inMemory(), repository: repository)
        #expect(model.showsCards)
        let list = try #require(model.makeCardListModel())
        #expect(list.cards.map(\.name) == ["Bonus"])
    }
}

@MainActor
@Suite("Home settings Cards wiring")
struct HomeSettingsCardsWiringTests {
    @Test("Settings made by Home show the Cards row on Home's repository")
    func homeSettingsHasCards() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
        let repository = InMemoryPaymentRepository()
        try repository.save(Fixture.card("Bonus"))
        let home = HomeViewModel(
            repository: repository, today: today, calendar: calendar,
            settings: SettingsDependencies(store: InMemoryReminderPreferencesStore())
        )
        let settings = home.makeSettingsModel()
        #expect(settings.showsCards)
        #expect(settings.makeCardListModel()?.cards.map(\.name) == ["Bonus"])
    }
}
