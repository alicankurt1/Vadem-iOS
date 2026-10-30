import Testing
import VademCore
import VademTestSupport

// Bellek içi referans gelen kutusu, ortak sözleşmenin tamamından geçer.
struct InboxRepositoryFactory: Sendable, CustomTestStringConvertible {
    let name: String
    let make: @MainActor @Sendable () throws -> any InboxRepository

    var testDescription: String { name }

    static let all: [InboxRepositoryFactory] = [
        InboxRepositoryFactory(name: "InMemory") { InMemoryInboxRepository() },
    ]
}

@MainActor
@Suite("InboxRepository contract")
struct InboxRepositoryContractTests {
    @Test("Contract scenario", arguments: InboxRepositoryFactory.all, InboxRepositoryContract.scenarios)
    func contract(factory: InboxRepositoryFactory, scenario: InboxRepositoryContract.Scenario) throws {
        try scenario.run(factory.make())
    }

    @Test("The convenience init ignores a later entry with an id already given")
    func initIgnoresDuplicateIDs() throws {
        let first = try Fixture.inboxEntry(body: "İlk", createdAt: 1)
        let second = try Fixture.inboxEntry(body: "İkinci", createdAt: 2)
        let repo = InMemoryInboxRepository(entries: [first, second])
        #expect(try repo.entries() == [first])
    }
}
