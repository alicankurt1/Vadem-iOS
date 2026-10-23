import SwiftUI
import VademFeatures
import WidgetKit

/// "How much do I pay this month, and what is next?" on the home screen and the lock screen.
struct UpcomingPaymentsWidget: Widget {
    /// The widget kind; also the key for targeted reloads.
    static let kind = "com.alicankurt.Vadem.upcoming"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: UpcomingPaymentsProvider()) { entry in
            UpcomingPaymentsView(entry: entry)
        }
        .configurationDisplayName("Upcoming payments")
        .description("This month's total and your next payments.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

/// One moment of the widget: what ``WidgetTimelineBuilder`` decided to show from `date` on.
struct UpcomingPaymentsEntry: TimelineEntry, Sendable {
    let date: Date
    let content: WidgetTimelineBuilder.Content
}
