import Foundation
import Observation
import VademCore

/// Drives the ``InboxView``: the saved inbox entries, newest first.
///
/// The entries are loaded on init (``reload()`` loads them again). ``open()`` (the screen appeared)
/// marks them all read in the repository; the rows keep the unread marker they had when they were
/// loaded, so the user still sees what is new during this visit, and the next load shows them as
/// read. `onChange` runs after ``open()`` and ``delete(id:)`` (e.g. so Home updates its unread badge).
@MainActor
@Observable
public final class InboxViewModel: Identifiable {
    /// What the screen shows.
    public enum State: Sendable, Hashable {
        /// At least one entry.
        case loaded
        /// No entries.
        case empty
        /// The repository failed; `message` is shown to the user.
        case error(message: String)
    }

    /// One entry as the screen shows it.
    public struct Row: Sendable, Hashable, Identifiable {
        /// The entry's id (``InboxEntry/id``).
        public let id: String
        /// The entry's title.
        public let title: String
        /// The entry's text.
        public let body: String
        /// When the entry was produced, e.g. `"October 1, 2026"`.
        public let dateText: String
        /// `true` when the entry was unread when the inbox was opened.
        public let isUnread: Bool
        /// What VoiceOver reads for the row, e.g. `"Unread. Payments rose. Your payments rose 50% this month…. October 1, 2026"`.
        public let accessibilityLabel: String
    }

    /// The message shown when the entries could not be loaded.
    public nonisolated static var loadErrorMessage: String {
        String(localized: "Your notifications could not be loaded.", bundle: .module)
    }

    /// The model's identity (for `navigationDestination(item:)`).
    public nonisolated let id = UUID()

    /// What the screen shows.
    public private(set) var state: State = .empty
    /// The entries, newest first.
    public private(set) var rows: [Row] = []

    @ObservationIgnored private let repository: any InboxRepository
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let onChange: (@MainActor () -> Void)?

    /// Creates the model; dates are written with `locale` in `calendar`'s time zone.
    public init(
        repository: any InboxRepository,
        locale: Locale = VademLocalization.locale,
        calendar: Calendar = .current,
        onChange: (@MainActor () -> Void)? = nil
    ) {
        self.repository = repository
        self.locale = locale
        self.calendar = calendar
        self.onChange = onChange
        reload()
    }

    /// Loads the entries from the repository; a thrown error becomes ``State/error(message:)``.
    public func reload() {
        do {
            rows = try repository.entries().map(makeRow)
            state = rows.isEmpty ? .empty : .loaded
        } catch {
            rows = []
            state = .error(message: Self.loadErrorMessage)
        }
    }

    /// The screen appeared: marks every entry read (the rows keep their markers for this visit).
    public func open() {
        // Ekran açıldı: hepsi okundu sayılır; Home'daki rozet hemen temizlenir. Hata olursa rozet kalır.
        try? repository.markAllRead()
        onChange?()
    }

    /// New entries were added while the screen is open: reloads the rows (new ones keep their
    /// unread marker for this visit) and marks every entry read, like ``open()``.
    public func entriesAdded() {
        reload()
        open()
    }

    /// Deletes the entry with `id`; it does not come back on the next launch.
    public func delete(id: InboxEntry.ID) {
        do {
            try repository.delete(id: id)
            rows.removeAll { $0.id == id }
            if rows.isEmpty, state == .loaded { state = .empty }
        } catch {
            // Silinemezse satır yerinde kalır; liste diskteki veriyle tutarlıdır.
        }
        onChange?()
    }

    private func makeRow(_ entry: InboxEntry) -> Row {
        let dateText = Self.dateText(entry.createdAt, locale: locale, calendar: calendar)
        let parts = [
            entry.isRead ? nil : String(localized: "Unread", bundle: .module, comment: "VoiceOver prefix of an unread inbox entry"),
            entry.title, entry.body, dateText,
        ]
        return Row(
            id: entry.id, title: entry.title, body: entry.body, dateText: dateText, isUnread: !entry.isRead,
            accessibilityLabel: parts.compactMap { $0 }.joined(separator: ". ")
        )
    }

    /// `date` as a day, e.g. `"October 1, 2026"` (English) or `"1 Ekim 2026"` (Turkish).
    nonisolated static func dateText(_ date: Date, locale: Locale, calendar: Calendar) -> String {
        var style = Date.FormatStyle(date: .long, time: .omitted).locale(locale)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}
