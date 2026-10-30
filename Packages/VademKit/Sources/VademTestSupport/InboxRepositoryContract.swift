import Foundation
import Testing
import VademCore

// Gelen kutusu deposu sözleşmesi: her senaryo yalnızca `any InboxRepository` üzerinden çalışır.
// Her `InboxRepository` uygulaması (bellek içi, SwiftData, …) kendi test hedefinde aynı
// `scenarios` listesinden geçirilir: `@Test(arguments: factories, InboxRepositoryContract.scenarios)`.
@MainActor
public enum InboxRepositoryContract {
    public static func startsEmpty(_ repo: any InboxRepository) throws {
        #expect(try repo.entries().isEmpty)
        #expect(try repo.unreadCount() == 0)
    }

    public static func addedEntryComesBackExactly(_ repo: any InboxRepository) throws {
        // Kesirli saniye ve Türkçe karakterler aynen geri okunur.
        let entry = try Fixture.inboxEntry(
            .installmentEnded, month: Fixture.month(2031, 12), title: "Taksit bitti",
            body: "Dizüstü: taksit bitti; bu ay ₺1.234.567,89 daha az ödüyorsun", createdAt: 812_345_678.25
        )
        #expect(try repo.add(entry))
        #expect(try repo.entries() == [entry])
        #expect(try repo.unreadCount() == 1)
    }

    public static func entriesAreNewestFirst(_ repo: any InboxRepository) throws {
        // Ters sırada eklenir: yeni olan (createdAt büyük) önce gelir.
        let october = try Fixture.inboxEntry(month: Fixture.month(2026, 10), createdAt: 100)
        let november = try Fixture.inboxEntry(month: Fixture.month(2026, 11), createdAt: 200)
        let december = try Fixture.inboxEntry(month: Fixture.month(2026, 12), createdAt: 300)
        try repo.add(october)
        try repo.add(december)
        try repo.add(november)
        #expect(try repo.entries() == [december, november, october])
    }

    public static func sameTimeEntriesOrderedByMonthThenImportance(_ repo: any InboxRepository) throws {
        // Aynı anda üretilenler: önce yeni ay, aynı ayda önemli tür (toplam değişimi) önce.
        let month = try Fixture.month(2026, 11)
        let ended = try Fixture.inboxEntry(.installmentEnded, month: month, createdAt: 50)
        let change = try Fixture.inboxEntry(.totalChange, month: month, createdAt: 50)
        let older = try Fixture.inboxEntry(.totalChange, month: Fixture.month(2026, 10), createdAt: 50)
        try repo.add(older)
        try repo.add(ended)
        try repo.add(change)
        #expect(try repo.entries() == [change, ended, older])
    }

    public static func addingSameIDTwiceKeepsTheFirst(_ repo: any InboxRepository) throws {
        // Yeniden açılışta aynı içgörü tekrar üretilir; ilk kayıt (metni ve okundu durumu) korunur.
        let first = try Fixture.inboxEntry(body: "İlk metin", createdAt: 10)
        let again = try Fixture.inboxEntry(body: "Yeni metin", createdAt: 20)
        #expect(try repo.add(first))
        try repo.markAllRead()
        #expect(try !repo.add(again))
        let stored = try repo.entries()
        #expect(stored.count == 1)
        #expect(stored.first?.body == "İlk metin")
        #expect(stored.first?.isRead == true)
        #expect(try repo.unreadCount() == 0)
    }

    public static func markAllReadClearsUnreadCount(_ repo: any InboxRepository) throws {
        try repo.add(Fixture.inboxEntry(.totalChange, createdAt: 1))
        try repo.add(Fixture.inboxEntry(.installmentEnded, createdAt: 2))
        try repo.add(Fixture.inboxEntry(month: Fixture.month(2026, 10), createdAt: 3, isRead: true))
        #expect(try repo.unreadCount() == 2)
        try repo.markAllRead()
        #expect(try repo.unreadCount() == 0)
        #expect(try repo.entries().allSatisfy(\.isRead))
        #expect(try repo.entries().count == 3)
    }

    public static func entriesAddedAfterMarkAllReadAreUnread(_ repo: any InboxRepository) throws {
        try repo.add(Fixture.inboxEntry(month: Fixture.month(2026, 10), createdAt: 1))
        try repo.markAllRead()
        let new = try Fixture.inboxEntry(month: Fixture.month(2026, 11), createdAt: 2)
        try repo.add(new)
        #expect(try repo.unreadCount() == 1)
        #expect(try repo.entries().first == new)
    }

    public static func deletesOneEntry(_ repo: any InboxRepository) throws {
        let keep = try Fixture.inboxEntry(.totalChange, createdAt: 1)
        let remove = try Fixture.inboxEntry(.installmentEnded, createdAt: 2)
        try repo.add(keep)
        try repo.add(remove)
        try repo.delete(id: remove.id)
        #expect(try repo.entries() == [keep])
        #expect(try repo.unreadCount() == 1)
    }

    public static func deletedEntryIsNeverAddedAgain(_ repo: any InboxRepository) throws {
        // Mezar taşı: silinen içgörü bir sonraki açılışta geri gelmez.
        let entry = try Fixture.inboxEntry(createdAt: 1)
        try repo.add(entry)
        try repo.delete(id: entry.id)
        #expect(try !repo.add(Fixture.inboxEntry(createdAt: 99)))
        #expect(try repo.entries().isEmpty)
        #expect(try repo.unreadCount() == 0)
    }

    public static func deletingUnknownIDIsNoOp(_ repo: any InboxRepository) throws {
        // Bilinmeyen id silinirse hiçbir şey değişmez ve o id sonradan eklenebilir.
        let entry = try Fixture.inboxEntry(.totalChange, createdAt: 1)
        try repo.add(entry)
        let unknown = try Fixture.inboxEntry(.installmentEnded, createdAt: 2)
        try repo.delete(id: unknown.id)
        #expect(try repo.entries() == [entry])
        #expect(try repo.add(unknown))
        #expect(try repo.entries() == [unknown, entry])
    }

    public static func markAllReadOnEmptyIsNoOp(_ repo: any InboxRepository) throws {
        try repo.markAllRead()
        #expect(try repo.entries().isEmpty)
        #expect(try repo.unreadCount() == 0)
    }

    /// Her senaryo bir test olarak koşar; adı test raporunda görünür.
    public struct Scenario: Sendable, CustomTestStringConvertible {
        public let name: String
        public let run: @MainActor @Sendable (any InboxRepository) throws -> Void
        public var testDescription: String { name }
    }

    /// Sözleşmenin tamamı. Yeni bir uygulama bu listeyi `@Test(arguments: factories, scenarios)` ile koşar.
    nonisolated public static let scenarios: [Scenario] = [
        Scenario(name: "A new inbox is empty", run: startsEmpty),
        Scenario(name: "An added entry comes back exactly", run: addedEntryComesBackExactly),
        Scenario(name: "Entries are newest first", run: entriesAreNewestFirst),
        Scenario(name: "Entries created together are ordered by month, then importance", run: sameTimeEntriesOrderedByMonthThenImportance),
        Scenario(name: "Adding an id twice keeps the first entry and its read state", run: addingSameIDTwiceKeepsTheFirst),
        Scenario(name: "Marking all read clears the unread count", run: markAllReadClearsUnreadCount),
        Scenario(name: "Entries added after marking all read are unread", run: entriesAddedAfterMarkAllReadAreUnread),
        Scenario(name: "One entry can be deleted", run: deletesOneEntry),
        Scenario(name: "A deleted entry is never added again", run: deletedEntryIsNeverAddedAgain),
        Scenario(name: "Deleting an unknown id is a no-op", run: deletingUnknownIDIsNoOp),
        Scenario(name: "Marking all read on an empty inbox is a no-op", run: markAllReadOnEmptyIsNoOp),
    ]
}
