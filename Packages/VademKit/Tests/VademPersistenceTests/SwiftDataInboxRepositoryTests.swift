import Foundation
import SwiftData
import Testing
import VademCore
@testable import VademPersistence
import VademTestSupport

// SwiftData gelen kutusu, bellek içi referansla aynı sözleşmeden geçer.
struct SwiftDataInboxFactory: Sendable, CustomTestStringConvertible {
    let name: String
    let make: @MainActor @Sendable () throws -> any InboxRepository

    var testDescription: String { name }

    static let all: [SwiftDataInboxFactory] = [
        SwiftDataInboxFactory(name: "SwiftData (in-memory)") {
            try SwiftDataInboxRepository(container: VademPersistence.makeContainer(storage: .inMemory))
        },
    ]
}

@MainActor
@Suite("SwiftDataInboxRepository contract")
struct SwiftDataInboxRepositoryContractTests {
    @Test("Contract scenario", arguments: SwiftDataInboxFactory.all, InboxRepositoryContract.scenarios)
    func contract(factory: SwiftDataInboxFactory, scenario: InboxRepositoryContract.Scenario) throws {
        try scenario.run(factory.make())
    }
}

// Diske yazılıp yeni kapla açılan depo: okundu durumu ve silinenler "yeniden açılışta" korunur.
@MainActor
@Suite("SwiftDataInboxRepository persistence")
struct SwiftDataInboxRepositoryPersistenceTests {
    @Test("Entries and their read state survive a reopen")
    func entriesSurvive() throws {
        try TemporaryStore.with { url in
            let read = try Fixture.inboxEntry(.totalChange, month: Fixture.month(2026, 10), createdAt: 1)
            let unread = try Fixture.inboxEntry(.installmentEnded, month: Fixture.month(2026, 11), createdAt: 2)
            do {
                let repo = try SwiftDataInboxRepository(container: VademPersistence.makeContainer(storage: .file(url)))
                try repo.add(read)
                try repo.markAllRead()
                try repo.add(unread)
            }
            let reopened = try SwiftDataInboxRepository(container: VademPersistence.makeContainer(storage: .file(url)))
            var expectedRead = read
            expectedRead.isRead = true
            #expect(try reopened.entries() == [unread, expectedRead])
            #expect(try reopened.unreadCount() == 1)
        }
    }

    @Test("A deleted entry is not added again after a reopen")
    func tombstoneSurvives() throws {
        try TemporaryStore.with { url in
            let entry = try Fixture.inboxEntry(createdAt: 1)
            do {
                let repo = try SwiftDataInboxRepository(container: VademPersistence.makeContainer(storage: .file(url)))
                try repo.add(entry)
                try repo.delete(id: entry.id)
            }
            let reopened = try SwiftDataInboxRepository(container: VademPersistence.makeContainer(storage: .file(url)))
            #expect(try !reopened.add(entry))
            #expect(try reopened.entries().isEmpty)
        }
    }

    @Test("Payments and inbox share one container without disturbing each other")
    func sharedContainer() throws {
        let container = try VademPersistence.makeContainer(storage: .inMemory)
        let payments = SwiftDataPaymentRepository(container: container)
        let inbox = SwiftDataInboxRepository(container: container)
        let card = try Fixture.card("Bonus", id: Fixture.id(1))
        try payments.save(card)
        try inbox.add(Fixture.inboxEntry(createdAt: 1))
        #expect(try payments.cards() == [card])
        #expect(try inbox.entries().count == 1)
    }
}
