import Foundation
import VademCore
import VademFeatures
import VademPersistence
import WidgetKit

/// Reads the App Group store and maps ``WidgetTimelineBuilder``'s result to a WidgetKit timeline.
struct UpcomingPaymentsProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpcomingPaymentsEntry {
        UpcomingPaymentsEntry.sample(now: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (UpcomingPaymentsEntry) -> Void) {
        // Galeri önizlemesi örnek rakamlarla; gerçek veri zaman çizelgesinde.
        if context.isPreview {
            completion(UpcomingPaymentsEntry.sample(now: Date()))
            return
        }
        Task { @MainActor in
            let result = Self.makeTimeline(now: Date())
            completion(result.entries.first ?? UpcomingPaymentsEntry(date: Date(), content: .unavailable))
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<UpcomingPaymentsEntry>) -> Void) {
        Task { @MainActor in
            let result = Self.makeTimeline(now: Date())
            completion(Timeline(entries: result.entries, policy: .after(result.reloadDate)))
        }
    }

    // Depo açılamazsa da çökülmez: tek "açılamadı" girdisi, bir saat sonra yeniden denenir.
    @MainActor
    private static func makeTimeline(now: Date) -> (entries: [UpcomingPaymentsEntry], reloadDate: Date) {
        let repository: any PaymentRepository
        do {
            let container = try VademPersistence.makeContainer(storage: .appGroup)
            repository = SwiftDataPaymentRepository(container: container)
        } catch {
            return (
                [UpcomingPaymentsEntry(date: now, content: .unavailable)],
                now.addingTimeInterval(WidgetTimelineBuilder.retryInterval)
            )
        }
        let result = WidgetTimelineBuilder(repository: repository, calendar: .current).timeline(now: now)
        return (result.entries.map { UpcomingPaymentsEntry(date: $0.date, content: $0.content) }, result.reloadDate)
    }
}

extension UpcomingPaymentsEntry {
    /// Sample numbers for the placeholder and the widget gallery: three subscriptions due
    /// today, in two days and in five days (clamped to the month's last day).
    static func sample(now: Date, calendar: Calendar = .current) -> UpcomingPaymentsEntry {
        let month = YearMonth(date: now, calendar: calendar)
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let today = gregorian.component(.day, from: now)
        // Örnek abonelikler geçen ay başlar ki bu ay kesin çekilsin.
        let start = month.adding(months: -1)
        let samples: [(String, Decimal, Int)] = [
            ("Rent", 25_000, today),
            ("Gym", 900, today + 2),
            ("Netflix", Decimal(24_999) / 100, today + 5),
        ]
        let subscriptions = samples.compactMap { title, amount, day -> SubscriptionItem? in
            guard let subscription = Subscription(
                amount: Money(amount), period: .monthly, renewalDay: min(day, 31), firstMonth: start
            ) else { return nil }
            return SubscriptionItem(title: title, cardID: nil, subscription: subscription)
        }
        let summary = PaymentSummary(
            now: now, calendar: calendar, cards: [], installments: [], subscriptions: subscriptions
        )
        return UpcomingPaymentsEntry(date: now, content: .summary(summary))
    }
}
