import SwiftUI
import VademCore

/// One payment in a list: a day-of-month circle tinted by how soon it is due, title,
/// subtitle, amount and a ``DueChip``. VoiceOver reads it as one element.
@MainActor
public struct PaymentRow: View {
    private let day: Int
    private let title: String
    private let subtitle: String?
    private let amount: Money
    private let dueTitle: String
    private let dueKind: DueChip.Kind

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // Gün dairesi metinle birlikte büyür.
    @ScaledMetric(relativeTo: .body) private var circleSize: CGFloat = 40

    /// Creates a row for a payment due on `day` (day of month), with chip text `dueTitle` of `dueKind`.
    public init(
        day: Int,
        title: String,
        subtitle: String? = nil,
        amount: Money,
        dueTitle: String,
        dueKind: DueChip.Kind
    ) {
        self.day = day
        self.title = title
        self.subtitle = subtitle
        self.amount = amount
        self.dueTitle = dueTitle
        self.dueKind = dueKind
    }

    public var body: some View {
        // Normal boyutlarda yan yana, erişilebilirlik boyutlarında alt alta (ChoiceRow gibi AnyLayout:
        // metinlerin kimliği korunur).
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            dayCircle
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.vademTextPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.vademTextSecondary)
                }
            }
            .multilineTextAlignment(.leading)
            if !stacked { Spacer(minLength: 8) }
            VStack(alignment: stacked ? .leading : .trailing, spacing: 6) {
                AmountText(amount)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.vademTextPrimary)
                DueChip(dueTitle, kind: dueKind)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Satır VoiceOver'da tek öğe; etiket saf fonksiyondan gelir.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Self.accessibilityLabel(day: day, title: title, subtitle: subtitle, amount: amount, dueTitle: dueTitle)
        )
    }

    // Ayın günü, çipin renk çiftiyle (aynı token çifti kontrast testinde).
    private var dayCircle: some View {
        Text(String(day))
            .font(.callout.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(dueKind.foreground)
            .frame(width: circleSize, height: circleSize)
            .background(dueKind.background, in: .circle)
    }

    /// The row's VoiceOver label: day, title, subtitle (if any), spoken amount and chip text,
    /// e.g. `"Day 15, Netflix, Subscription, 99,99 Türk lirası, Today"`.
    ///
    /// Pure; the amount uses ``AmountText/spokenLabel(_:)`` (no `₺` symbol).
    public nonisolated static func accessibilityLabel(
        day: Int,
        title: String,
        subtitle: String? = nil,
        amount: Money,
        dueTitle: String
    ) -> String {
        var parts = ["Day \(day)", title]
        if let subtitle, !subtitle.isEmpty {
            parts.append(subtitle)
        }
        parts.append(AmountText.spokenLabel(amount))
        parts.append(dueTitle)
        return parts.joined(separator: ", ")
    }
}

#Preview {
    VStack {
        PaymentRow(
            day: 15, title: "Netflix", subtitle: "Subscription",
            amount: Money(Decimal(9_999) / 100), dueTitle: "Today", dueKind: .today
        )
        PaymentRow(day: 3, title: "Laptop", amount: Money(2_500), dueTitle: "Later", dueKind: .later)
    }
    .padding()
}
