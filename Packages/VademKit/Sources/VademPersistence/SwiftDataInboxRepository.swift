import Foundation
import SwiftData
import VademCore

/// An ``InboxRepository`` that stores the inbox with SwiftData.
///
/// Behaves exactly like `InMemoryInboxRepository`: same order, same rules. A deleted entry stays
/// as a tombstone record (no text), so its id is never added again. Every write is saved
/// immediately; a failed save is rolled back and rethrown. Reading a record that cannot be turned
/// back into an ``InboxEntry`` throws ``PersistenceError/invalidInboxEntry(id:)``.
@MainActor
public final class SwiftDataInboxRepository: InboxRepository {
    // Context, container'ı canlı tutmaz; container depo ömrü boyunca burada tutulur.
    private let container: ModelContainer
    private let context: ModelContext

    /// Creates a repository on `container`'s main context and keeps the container alive.
    /// Use ``VademPersistence/makeContainer(storage:)`` to create the container (the same one
    /// as the `SwiftDataPaymentRepository` is fine).
    public init(container: ModelContainer) {
        self.container = container
        context = container.mainContext
    }

    public func entries() throws -> [InboxEntry] {
        try context.fetch(FetchDescriptor<InboxEntryRecord>(predicate: #Predicate { !$0.isTombstone }))
            .map { try $0.value() }
            .sorted(by: InboxEntry.isOrdered)
    }

    @discardableResult
    public func add(_ entry: InboxEntry) throws -> Bool {
        // Görülmüş id (kayıtlı ya da mezar taşı) yok sayılır: metin ve okundu durumu korunur.
        let id = entry.id
        let seen = try context.fetchCount(FetchDescriptor<InboxEntryRecord>(predicate: #Predicate { $0.id == id }))
        guard seen == 0 else { return false }
        context.insert(InboxEntryRecord(entry))
        try commit()
        return true
    }

    public func markAllRead() throws {
        let unread = try context.fetch(FetchDescriptor<InboxEntryRecord>(predicate: #Predicate { !$0.isRead }))
        guard !unread.isEmpty else { return }
        for record in unread {
            record.isRead = true
        }
        try commit()
    }

    public func delete(id: InboxEntry.ID) throws {
        let descriptor = FetchDescriptor<InboxEntryRecord>(predicate: #Predicate { $0.id == id && !$0.isTombstone })
        guard let record = try context.fetch(descriptor).first else { return }
        // Kayıt silinmez, mezar taşına döner: metin boşaltılır, id kalır.
        record.isTombstone = true
        record.isRead = true
        record.title = ""
        record.body = ""
        try commit()
    }

    public func unreadCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<InboxEntryRecord>(predicate: #Predicate { !$0.isRead && !$0.isTombstone }))
    }

    // Her yazma hemen kaydedilir; başarısızsa bekleyen değişiklikler geri alınır.
    private func commit() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
