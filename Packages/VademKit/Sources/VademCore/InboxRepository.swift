import Foundation

/// Saves and loads the in-app inbox: its entries and their read state.
///
/// Rules every implementation keeps (``InMemoryInboxRepository`` is the reference):
/// - ``entries()`` are newest first (``InboxEntry/isOrdered(_:before:)``).
/// - ``add(_:)`` ignores an entry whose id the repository has already seen, whether it is still
///   stored or was deleted: a deleted entry stays seen (a tombstone), so the same insight does not
///   come back on the next launch, and a stored entry keeps its text and read state.
/// - ``delete(id:)`` of an unknown id is a no-op (it does not mark the id as seen).
@MainActor
public protocol InboxRepository {
    /// The stored entries (deleted ones excluded), newest first.
    func entries() throws -> [InboxEntry]
    /// Stores `entry` unless its id was seen before (stored or deleted); returns `true` when it was added.
    @discardableResult
    func add(_ entry: InboxEntry) throws -> Bool
    /// Marks every stored entry as read.
    func markAllRead() throws
    /// Deletes the entry with `id`; it is never added again. An unknown `id` is a no-op.
    func delete(id: InboxEntry.ID) throws
    /// The number of stored entries that are not read.
    func unreadCount() throws -> Int
}

/// An ``InboxRepository`` that keeps everything in memory.
///
/// The reference implementation of the inbox rules, used for previews, sample data and tests.
/// Nothing is persisted; a new instance starts empty.
@MainActor
public final class InMemoryInboxRepository: InboxRepository {
    private var entriesByID: [InboxEntry.ID: InboxEntry] = [:]
    // Silinen id'ler (mezar taşı): aynı içgörü yeniden eklenmez.
    private var deletedIDs: Set<InboxEntry.ID> = []

    /// Creates an empty repository.
    public init() {}

    /// Creates a repository holding `entries` (later ones with an id already given are ignored).
    public convenience init(entries: [InboxEntry]) {
        self.init()
        for entry in entries where entriesByID[entry.id] == nil {
            entriesByID[entry.id] = entry
        }
    }

    public func entries() throws -> [InboxEntry] {
        entriesByID.values.sorted(by: InboxEntry.isOrdered)
    }

    @discardableResult
    public func add(_ entry: InboxEntry) throws -> Bool {
        // Görülmüş id (kayıtlı ya da silinmiş) yok sayılır: metin ve okundu durumu korunur.
        guard entriesByID[entry.id] == nil, !deletedIDs.contains(entry.id) else { return false }
        entriesByID[entry.id] = entry
        return true
    }

    public func markAllRead() throws {
        for id in entriesByID.keys {
            entriesByID[id]?.isRead = true
        }
    }

    public func delete(id: InboxEntry.ID) throws {
        guard entriesByID.removeValue(forKey: id) != nil else { return }
        deletedIDs.insert(id)
    }

    public func unreadCount() throws -> Int {
        entriesByID.values.filter { !$0.isRead }.count
    }
}
