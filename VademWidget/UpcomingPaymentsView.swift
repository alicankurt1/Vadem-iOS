import SwiftUI
import VademCore
import VademFeatures
import WidgetKit

/// The widget's face for every supported family.
///
/// Home-screen families sit on the hero background with `heroText` / `heroSecondary` text;
/// the lock screen uses the system tint. The accent is used only as a fill, never as text.
struct UpcomingPaymentsView: View {
    let entry: UpcomingPaymentsEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                // Kilit ekranında arka plan ve renkler sistemden gelir.
                if isAccessory {
                    Color.clear
                } else {
                    Color.vademHero
                }
            }
    }

    private var isAccessory: Bool {
        family == .accessoryRectangular
    }

    @ViewBuilder
    private var content: some View {
        switch entry.content {
        case .summary(let summary):
            switch family {
            case .systemMedium:
                MediumSummaryView(summary: summary)
            case .accessoryRectangular:
                AccessorySummaryView(summary: summary)
            default:
                SmallSummaryView(summary: summary)
            }
        case .empty:
            MessageView(title: "Nothing due", detail: "Add a payment in Vadem", isAccessory: isAccessory)
        case .unavailable:
            MessageView(title: "Payments unavailable", detail: "Open Vadem to try again", isAccessory: isAccessory)
        }
    }
}

// MARK: - Aileler

/// Small: the month total and the next payment.
private struct SmallSummaryView: View {
    let summary: PaymentSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This month")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.vademHeroSecondary)
            AmountText(summary.monthTotal)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.vademHeroText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            if let next = summary.next.first {
                NextPaymentView(payment: next)
            } else {
                Text("No upcoming payments")
                    .font(.caption)
                    .foregroundStyle(Color.vademHeroSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Medium: the month total and "left to pay" on the left, up to three upcoming rows on the right.
private struct MediumSummaryView: View {
    let summary: PaymentSummary

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("This month")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.vademHeroSecondary)
                AmountText(summary.monthTotal)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.vademHeroText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 4)
                Text("Left to pay")
                    .font(.caption)
                    .foregroundStyle(Color.vademHeroSecondary)
                AmountText(summary.remaining)
                    .font(.headline)
                    .foregroundStyle(Color.vademHeroText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 8) {
                if summary.next.isEmpty {
                    Text("No upcoming payments")
                        .font(.caption)
                        .foregroundStyle(Color.vademHeroSecondary)
                } else {
                    ForEach(summary.next, id: \.self) { payment in
                        UpcomingRowView(payment: payment)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Lock screen: the month total and the next payment, in the system tint.
private struct AccessorySummaryView: View {
    let summary: PaymentSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("This month")
                AmountText(summary.monthTotal)
            }
            .font(.headline)
            // Başlık ve tutar tek satırda kalır; yer yetmezse küçülür.
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .widgetAccentable()
            if let next = summary.next.first {
                Text("\(next.title) \(AmountText.format(next.amount)), \(DayText.text(daysUntil: next.daysUntil))")
                    .font(.caption)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    // VoiceOver "₺" yerine okunabilir tutarı duyar.
                    .accessibilityLabel(DayText.accessibilityLabel(for: next))
            } else {
                Text("No upcoming payments")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Parçalar

/// The next payment on the hero background: an accent bar, the title, the amount and the day.
private struct NextPaymentView: View {
    let payment: PaymentSummary.Upcoming

    var body: some View {
        HStack(spacing: 6) {
            // Vurgu rengi yalnızca dolgu olarak: başlığın yanında ince bir çubuk.
            Capsule()
                .fill(Color.vademAccent)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(payment.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.vademHeroText)
                    .lineLimit(1)
                AmountText(payment.amount)
                    .font(.caption)
                    .foregroundStyle(Color.vademHeroText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(DayText.text(daysUntil: payment.daysUntil))
                    .font(.caption2)
                    .foregroundStyle(Color.vademHeroSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        // Satır VoiceOver'da tek öğe: başlık, okunabilir tutar, gün.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DayText.accessibilityLabel(for: payment))
    }
}

/// One upcoming row of the medium widget: day number, title, amount.
private struct UpcomingRowView: View {
    let payment: PaymentSummary.Upcoming

    var body: some View {
        HStack(spacing: 8) {
            Text("\(payment.dueDate.day)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.vademOnAccent)
                .frame(width: 24, height: 24)
                // Vurgu yalnızca dolgu; üstündeki gün numarası onAccent.
                .background(Color.vademAccent, in: Circle())
            Text(payment.title)
                .font(.caption)
                .foregroundStyle(Color.vademHeroText)
                .lineLimit(1)
            Spacer(minLength: 4)
            AmountText(payment.amount)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.vademHeroText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        // Satır VoiceOver'da tek öğe: başlık, okunabilir tutar, gün.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DayText.accessibilityLabel(for: payment))
    }
}

/// The empty and unavailable states.
private struct MessageView: View {
    let title: String
    let detail: String
    let isAccessory: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(isAccessory ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.vademHeroText))
                .widgetAccentable()
            Text(detail)
                .font(.caption)
                .foregroundStyle(isAccessory ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.vademHeroSecondary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isAccessory ? .leading : .topLeading)
    }
}

/// "Today", "Tomorrow" or "in N days", and the spoken row label built from it.
enum DayText {
    static func text(daysUntil: Int) -> String {
        switch daysUntil {
        case ...0: "Today"
        case 1: "Tomorrow"
        default: "in \(daysUntil) days"
        }
    }

    /// The VoiceOver label of a payment row: `"Rent, 25.000,00 Türk lirası, today"` (no "₺").
    static func accessibilityLabel(for payment: PaymentSummary.Upcoming) -> String {
        let day: String
        switch payment.daysUntil {
        case ...0: day = "today"
        case 1: day = "tomorrow"
        default: day = "in \(payment.daysUntil) days"
        }
        return "\(payment.title), \(AmountText.spokenLabel(payment.amount)), \(day)"
    }
}

#if DEBUG
#Preview("Small", as: .systemSmall) {
    UpcomingPaymentsWidget()
} timeline: {
    UpcomingPaymentsEntry.sample(now: .now)
    UpcomingPaymentsEntry(date: .now, content: .empty)
    UpcomingPaymentsEntry(date: .now, content: .unavailable)
}

#Preview("Medium", as: .systemMedium) {
    UpcomingPaymentsWidget()
} timeline: {
    UpcomingPaymentsEntry.sample(now: .now)
    UpcomingPaymentsEntry(date: .now, content: .empty)
}

#Preview("Lock screen", as: .accessoryRectangular) {
    UpcomingPaymentsWidget()
} timeline: {
    UpcomingPaymentsEntry.sample(now: .now)
    UpcomingPaymentsEntry(date: .now, content: .empty)
}
#endif
