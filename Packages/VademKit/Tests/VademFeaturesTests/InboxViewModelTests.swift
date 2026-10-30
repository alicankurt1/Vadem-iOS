import Foundation
import Testing
import VademCore
import VademFeatures
import VademTestSupport

@MainActor
@Suite("InboxViewModel")
struct InboxViewModelTests {
    private static let locale = Locale(identifier: "en_US")

    private static func model(
        _ repository: any InboxRepository, onChange: (@MainActor () -> Void)? = nil
    ) -> InboxViewModel {
        InboxViewModel(repository: repository, locale: locale, calendar: InboxTestSupport.calendar, onChange: onChange)
    }

    @Test("An empty inbox shows the empty state")
    func emptyState() {
        let model = Self.model(InMemoryInboxRepository())
        #expect(model.state == .empty)
        #expect(model.rows.isEmpty)
    }

    @Test("Entries load newest first with title, body and date")
    func loadsRows() throws {
        let old = try Fixture.inboxEntry(.totalChange, month: Fixture.month(2026, 9), title: "Eski", body: "b1", createdAt: 100, isRead: true)
        let new = try Fixture.inboxEntry(.totalChange, month: Fixture.month(2026, 10), title: "Yeni", body: "b2", createdAt: 200)
        let model = Self.model(InMemoryInboxRepository(entries: [old, new]))
        #expect(model.state == .loaded)
        #expect(model.rows.map(\.id) == [new.id, old.id])
        #expect(model.rows.map(\.title) == ["Yeni", "Eski"])
        #expect(model.rows.map(\.body) == ["b2", "b1"])
        // Referans tarihi 2001-01-01 UTC.
        #expect(model.rows.first?.dateText == "January 1, 2001")
    }

    @Test("Unread rows are marked unread and read rows are not")
    func unreadMarkers() throws {
        let read = try Fixture.inboxEntry(.installmentEnded, createdAt: 1, isRead: true)
        let unread = try Fixture.inboxEntry(.totalChange, createdAt: 2)
        let model = Self.model(InMemoryInboxRepository(entries: [read, unread]))
        #expect(model.rows.map(\.isUnread) == [true, false])
    }

    @Test("VoiceOver label joins title, body and date, with Unread first for unread rows")
    func accessibilityLabel() throws {
        let read = try Fixture.inboxEntry(.installmentEnded, title: "Titel", body: "Text", createdAt: 1, isRead: true)
        let unread = try Fixture.inboxEntry(.totalChange, title: "Titel", body: "Text", createdAt: 2)
        let model = Self.model(InMemoryInboxRepository(entries: [read, unread]))
        let unreadLabel = try #require(model.rows.first).accessibilityLabel
        let readLabel = try #require(model.rows.last).accessibilityLabel
        #expect(unreadLabel.hasPrefix("Unread. Titel. Text. "))
        #expect(readLabel.hasPrefix("Titel. Text. "))
        #expect(!readLabel.contains("Unread"))
    }

    @Test("Opening marks every entry read in the repository, rows keep their marker, onChange runs")
    func openMarksRead() throws {
        let repository = InMemoryInboxRepository(entries: [
            try Fixture.inboxEntry(.totalChange, createdAt: 1), try Fixture.inboxEntry(.installmentEnded, createdAt: 2),
        ])
        var changes = 0
        let model = Self.model(repository) { changes += 1 }
        #expect(try repository.unreadCount() == 2)
        model.open()
        #expect(try repository.unreadCount() == 0)
        #expect(changes == 1)
        // Bu ziyarette satırlar yeni olduklarını gösterir; sonraki yüklemede okundu görünürler.
        #expect(model.rows.allSatisfy { $0.isUnread })
        model.reload()
        #expect(model.rows.allSatisfy { !$0.isUnread })
    }

    @Test("Deleting removes the row, keeps the others and calls onChange")
    func deleteRow() throws {
        let keep = try Fixture.inboxEntry(.totalChange, createdAt: 2)
        let remove = try Fixture.inboxEntry(.installmentEnded, createdAt: 1)
        let repository = InMemoryInboxRepository(entries: [keep, remove])
        var changes = 0
        let model = Self.model(repository) { changes += 1 }
        model.delete(id: remove.id)
        #expect(model.rows.map(\.id) == [keep.id])
        #expect(model.state == .loaded)
        #expect(try repository.entries() == [keep])
        #expect(changes == 1)
    }

    @Test("Deleting the last entry shows the empty state and the entry stays gone")
    func deleteLast() throws {
        let entry = try Fixture.inboxEntry(createdAt: 1)
        let repository = InMemoryInboxRepository(entries: [entry])
        let model = Self.model(repository)
        model.delete(id: entry.id)
        #expect(model.state == .empty)
        #expect(try !repository.add(entry))
    }

    @Test("A failing repository gives the error state")
    func errorState() {
        let model = Self.model(InboxTestSupport.FailingInbox())
        #expect(model.state == .error(message: InboxViewModel.loadErrorMessage))
        #expect(model.rows.isEmpty)
        #expect(!InboxViewModel.loadErrorMessage.isEmpty)
    }
}

@MainActor
@Suite("InboxRecorder")
struct InboxRecorderTests {
    @Test("Recording adds one entry per insight with the given text")
    func records() throws {
        let inbox = InMemoryInboxRepository()
        let recorder = InboxRecorder(
            payments: try InboxTestSupport.paymentsWithOneInsight(), inbox: inbox,
            text: { InboxPlanner.Text(title: "T \($0.kind.rawValue)", body: "B") }
        )
        let now = InboxTestSupport.date(2026, 11, 1)
        #expect(recorder.record(month: InboxTestSupport.november, at: now) == 1)
        let entries = try inbox.entries()
        #expect(entries.map(\.id) == ["insight-2026-11-totalChange"])
        #expect(entries.first?.title == "T totalChange")
        #expect(entries.first?.createdAt == now)
        #expect(entries.first?.isRead == false)
    }

    @Test("Recording again (a relaunch) adds nothing and keeps text and read state")
    func idempotent() throws {
        let inbox = InMemoryInboxRepository()
        let payments = try InboxTestSupport.paymentsWithOneInsight()
        let first = InboxRecorder(payments: payments, inbox: inbox, text: { _ in .init(title: "A", body: "a") })
        first.record(month: InboxTestSupport.november, at: InboxTestSupport.date(2026, 11, 1))
        try inbox.markAllRead()
        let second = InboxRecorder(payments: payments, inbox: inbox, text: { _ in .init(title: "B", body: "b") })
        #expect(second.record(month: InboxTestSupport.november, at: InboxTestSupport.date(2026, 11, 2)) == 0)
        #expect(try inbox.entries().count == 1)
        #expect(try inbox.entries().first?.title == "A")
        #expect(try inbox.unreadCount() == 0)
    }

    @Test("A deleted entry does not come back when recording again")
    func deletedStaysGone() throws {
        let inbox = InMemoryInboxRepository()
        let recorder = InboxRecorder(payments: try InboxTestSupport.paymentsWithOneInsight(), inbox: inbox)
        recorder.record(month: InboxTestSupport.november, at: InboxTestSupport.date(2026, 11, 1))
        try inbox.delete(id: "insight-2026-11-totalChange")
        #expect(recorder.record(month: InboxTestSupport.november, at: InboxTestSupport.date(2026, 11, 3)) == 0)
        #expect(try inbox.entries().isEmpty)
    }

    @Test("A month without insights adds nothing")
    func nothingToRecord() throws {
        let inbox = InMemoryInboxRepository()
        let recorder = InboxRecorder(payments: InMemoryPaymentRepository(), inbox: inbox)
        #expect(recorder.record(month: InboxTestSupport.november, at: InboxTestSupport.date(2026, 11, 1)) == 0)
        #expect(try inbox.entries().isEmpty)
    }

    @Test("A failing inbox does not crash and adds nothing")
    func failingInbox() throws {
        let recorder = InboxRecorder(
            payments: try InboxTestSupport.paymentsWithOneInsight(), inbox: InboxTestSupport.FailingInbox()
        )
        #expect(recorder.record(month: InboxTestSupport.november, at: InboxTestSupport.date(2026, 11, 1)) == 0)
    }
}

@MainActor
@Suite("Home inbox")
struct HomeInboxTests {
    private static func home(
        inbox: any InboxRepository, authorization: ReminderAuthorization = .allowed
    ) throws -> HomeViewModel {
        let center = ReminderSchedulerTests.FakeCenter(status: authorization)
        return HomeViewModel(
            repository: try InboxTestSupport.paymentsWithOneInsight(),
            today: InboxTestSupport.date(2026, 11, 10), calendar: InboxTestSupport.calendar,
            settings: SettingsDependencies(store: InMemoryReminderPreferencesStore(preferences: .default), center: center),
            inbox: inbox
        )
    }

    @Test("Recording insights raises the unread count; opening the inbox clears it")
    func badgeLifecycle() throws {
        let inbox = InMemoryInboxRepository()
        let home = try Self.home(inbox: inbox)
        #expect(home.inboxUnreadCount == 0)
        home.recordInsights(at: InboxTestSupport.date(2026, 11, 10))
        #expect(home.inboxUnreadCount == 1)

        let model = home.makeInboxModel()
        model.open()
        #expect(home.inboxUnreadCount == 0)
    }

    @Test("Recording twice does not raise the count again")
    func recordingTwice() throws {
        let home = try Self.home(inbox: InMemoryInboxRepository())
        home.recordInsights(at: InboxTestSupport.date(2026, 11, 10))
        home.recordInsights(at: InboxTestSupport.date(2026, 11, 11))
        #expect(home.inboxUnreadCount == 1)
    }

    @Test("Recording does not depend on notification authorization", arguments: [
        ReminderAuthorization.denied, .notDetermined, .allowed,
    ])
    func independentOfAuthorization(status: ReminderAuthorization) throws {
        let home = try Self.home(inbox: InMemoryInboxRepository(), authorization: status)
        home.recordInsights(at: InboxTestSupport.date(2026, 11, 10))
        #expect(home.inboxUnreadCount == 1)
    }

    @Test("updateToday (launch / foreground) records the current month's insights")
    func updateTodayRecords() throws {
        let home = try Self.home(inbox: InMemoryInboxRepository())
        home.updateToday(InboxTestSupport.date(2026, 11, 10))
        #expect(home.inboxUnreadCount == 1)
        home.updateToday(InboxTestSupport.date(2026, 11, 10))
        #expect(home.inboxUnreadCount == 1)
    }

    @Test("Deleting an entry in the inbox lowers the unread count")
    func deleteUpdatesBadge() throws {
        let home = try Self.home(inbox: InMemoryInboxRepository())
        home.recordInsights(at: InboxTestSupport.date(2026, 11, 10))
        let model = home.makeInboxModel()
        model.delete(id: "insight-2026-11-totalChange")
        #expect(home.inboxUnreadCount == 0)
    }

    @Test("An unreadable inbox shows no badge")
    func failingInboxNoBadge() throws {
        let home = try Self.home(inbox: InboxTestSupport.FailingInbox())
        home.recordInsights(at: InboxTestSupport.date(2026, 11, 10))
        #expect(home.inboxUnreadCount == 0)
    }

    @Test("requestInbox sets the flag once, takeInboxRequest clears it, and the count grows")
    func inboxRequest() throws {
        let home = try Self.home(inbox: InMemoryInboxRepository())
        #expect(!home.isInboxRequested)
        #expect(!home.takeInboxRequest())
        let before = home.inboxRequestCount
        home.requestInbox()
        #expect(home.isInboxRequested)
        #expect(home.inboxRequestCount == before + 1)
        #expect(home.takeInboxRequest())
        #expect(!home.isInboxRequested)
        #expect(!home.takeInboxRequest())
        home.requestInbox()
        #expect(home.inboxRequestCount == before + 2)
    }

    @Test("Sample inbox: two unread and one read entry, newest first")
    func sampleInbox() throws {
        let inbox = HomeSampleData.makeInboxRepository()
        let entries = try inbox.entries()
        #expect(entries.count == 3)
        #expect(try inbox.unreadCount() == 2)
        #expect(entries.map(\.isRead) == [false, false, true])
    }
}

@MainActor
@Suite("NotificationTapHandler")
struct NotificationTapHandlerTests {
    @Test("A monthly summary tap routes to the inbox")
    func summaryTap() {
        let handler = NotificationTapHandler()
        var routes: [NotificationRoute] = []
        handler.onRoute = { routes.append($0) }
        handler.handleTap(identifier: "insight-2026-11")
        #expect(routes == [.inbox])
    }

    @Test("A payment reminder tap routes nowhere", arguments: ["due-2026-11-15", "", "other"])
    func reminderTap(identifier: String) {
        let handler = NotificationTapHandler()
        var routes: [NotificationRoute] = []
        handler.onRoute = { routes.append($0) }
        handler.handleTap(identifier: identifier)
        #expect(routes.isEmpty)
    }

    @Test("A tap before onRoute is set waits and is delivered once")
    func coldLaunchTap() {
        let handler = NotificationTapHandler()
        handler.handleTap(identifier: "insight-2026-11")
        var routes: [NotificationRoute] = []
        handler.onRoute = { routes.append($0) }
        #expect(routes == [.inbox])
        handler.onRoute = { routes.append($0) }
        #expect(routes == [.inbox])
    }
}
