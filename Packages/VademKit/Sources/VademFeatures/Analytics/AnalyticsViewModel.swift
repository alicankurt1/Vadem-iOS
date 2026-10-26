import Foundation
import Observation
import VademCore

/// Drives the Analytics screen: the next 12 months' totals, split into installments and subscriptions.
///
/// "Today" is injected (`today` + `calendar`), never read from the clock. The model starts in
/// ``State/loading``; call ``reload()`` (the screen does it when it appears) to load the data.
@MainActor
@Observable
public final class AnalyticsViewModel {
    /// What the screen shows.
    public enum State: Sendable, Hashable {
        /// Nothing has been loaded yet.
        case loading
        /// At least one of the months has a payment.
        case loaded
        /// None of the months has a payment.
        case empty
        /// The repository failed; `message` is shown to the user.
        case error(message: String)
    }

    /// The figures of the selected month, ready to display.
    public struct Summary: Sendable, Hashable {
        /// The month.
        public let month: YearMonth
        /// The month as `"May 2026"`.
        public let title: String
        /// Installments + subscriptions of the month.
        public let total: Money
        /// The installment part of ``total``.
        public let installments: Money
        /// The subscription part of ``total``.
        public let subscriptions: Money
    }

    /// One slice of the selected month's card breakdown, ready to display.
    public struct CardShareRow: Sendable, Hashable, Identifiable {
        /// The card's id, or `"no-card"` for payments without a card.
        public let id: String
        /// The card's name, or "No card".
        public let name: String
        /// What the card is due in the month.
        public let amount: Money
        /// The whole-number share of the month's total; all rows sum to exactly 100.
        public let percent: Int
        /// The card's own style (`nil` for payments without a card).
        public let style: CardStyle?

        /// The row as one VoiceOver label: `"Night, 1.200,00 TL, 40 percent"`.
        public var accessibilityLabel: String {
            let amountText = AmountText.formattedMagnitude(amount)
            return String(
                localized: "\(name), \(amountText) TL, \(percent) percent", bundle: .module,
                comment: "Spoken card share: card name, amount, whole percent"
            )
        }
    }

    /// The last installment payment, ready to display.
    public struct Insight: Sendable, Hashable {
        /// `"Last installment payment: May 2027"`.
        public let title: String
        /// `"12 months remaining"`, `"Last payment this month"`, or `"Paid off"` when the last payment is in the past.
        public let remaining: String
        /// The months from the current month to the last payment, never negative.
        public let monthsRemaining: Int
    }

    /// The id of the ``CardShareRow`` of payments without a card.
    public nonisolated static let noCardID = "no-card"
    /// The number of months the chart shows.
    public nonisolated static let monthCount = 12
    /// The message of the ``State/error(message:)`` state.
    public nonisolated static var loadErrorMessage: String {
        String(localized: "Your payments could not be loaded.", bundle: .module)
    }

    /// The current state.
    public private(set) var state: State = .loading
    /// ``monthCount`` consecutive totals starting with ``currentMonth``; empty before loading and after an error.
    public private(set) var months: [SpendingAnalytics.MonthTotal] = []
    /// The month whose ``summary`` is shown; starts as ``currentMonth``.
    public private(set) var selectedMonth: YearMonth
    /// The month that contains the injected today.
    public let currentMonth: YearMonth

    /// The last installment payment; `nil` when there are no installments (the insight is hidden).
    public private(set) var insight: Insight?

    @ObservationIgnored private var analytics: SpendingAnalytics?
    @ObservationIgnored private let repository: any PaymentRepository

    /// Creates the view model for the month that contains `today` in `calendar`'s time zone.
    public convenience init(repository: any PaymentRepository, today: Date, calendar: Calendar) {
        self.init(repository: repository, currentMonth: YearMonth(date: today, calendar: calendar))
    }

    init(repository: any PaymentRepository, currentMonth: YearMonth) {
        self.repository = repository
        self.currentMonth = currentMonth
        self.selectedMonth = currentMonth
    }

    /// The selected month's figures, or `nil` while there are no ``months``.
    public var summary: Summary? {
        guard let total = months.first(where: { $0.month == selectedMonth }) else { return nil }
        return Summary(
            month: total.month, title: Self.title(of: total.month), total: total.total,
            installments: total.installments, subscriptions: total.subscriptions
        )
    }

    /// The selected month's card breakdown, largest first; empty when nothing is due that month.
    public var cardShares: [CardShareRow] {
        guard let analytics else { return [] }
        let shares = analytics.cardBreakdown(in: selectedMonth)
        let percents = Self.percentages(of: shares.map(\.total))
        return zip(shares, percents).map { share, percent in
            CardShareRow(
                id: share.card?.id.uuidString ?? Self.noCardID,
                name: share.card?.name ?? HomeViewModel.noCardText,
                amount: share.total,
                percent: percent,
                style: share.card.map { CardStyle.default(for: $0.id) }
            )
        }
    }

    /// Whole-number percentages of `amounts` in their total, by the largest-remainder method.
    ///
    /// The result has one entry per amount and sums to exactly 100 (all zeros when the total is
    /// not positive). Ties in the remainder go to the earlier amount.
    public nonisolated static func percentages(of amounts: [Money]) -> [Int] {
        let values = amounts.map { max($0.amount, 0) }
        let total = values.reduce(Decimal(0), +)
        guard total > 0 else { return values.map { _ in 0 } }
        let exact = values.map { $0 * 100 / total }
        var floors = exact.map { value -> Int in
            var rounded = Decimal()
            var source = value
            NSDecimalRound(&rounded, &source, 0, .down)
            return NSDecimalNumber(decimal: rounded).intValue
        }
        let order = exact.indices.sorted { lhs, rhs in
            let (a, b) = (exact[lhs] - Decimal(floors[lhs]), exact[rhs] - Decimal(floors[rhs]))
            return a != b ? a > b : lhs < rhs
        }
        for index in order.prefix(max(0, 100 - floors.reduce(0, +))) { floors[index] += 1 }
        return floors
    }

    /// Selects `month` for the summary; a month that is not one of ``months`` is ignored.
    public func select(month: YearMonth) {
        guard months.contains(where: { $0.month == month }) else { return }
        selectedMonth = month
    }

    /// Moves the selection `offset` months along ``months`` (VoiceOver's adjustable action);
    /// the selection stops at the first and last month.
    public func selectMonth(offsetBy offset: Int) {
        guard let index = months.firstIndex(where: { $0.month == selectedMonth }) else { return }
        let target = min(max(index + offset, 0), months.count - 1)
        selectedMonth = months[target].month
    }

    /// Loads the months from the repository; a thrown error becomes ``State/error(message:)``.
    ///
    /// Keeps the selected month while it is still shown, otherwise selects ``currentMonth``.
    public func reload() {
        do {
            let analytics = SpendingAnalytics(
                cards: try repository.cards(),
                installments: try repository.installments(),
                subscriptions: try repository.subscriptions()
            )
            self.analytics = analytics
            insight = analytics.lastPaymentMonth.map { last in
                let signed = currentMonth.months(until: last)
                let remaining = max(0, signed)
                let text = switch signed {
                case ..<0: String(localized: "Paid off", bundle: .module)
                case 0: String(localized: "Last payment this month", bundle: .module)
                // "1 month remaining" / "11 months remaining": katalogdaki çoğul varyasyonları.
                // Derlenmiş katalog yokken (`swift test`) "inflect" İngilizce çoğulu kurar.
                default: String(AttributedString(
                    localized: "^[\(remaining) month](inflect: true) remaining", bundle: .module,
                    comment: "Months until the last installment payment; plural variations in the catalog"
                ).characters)
                }
                let lastTitle = Self.title(of: last)
                return Insight(
                    title: String(
                        localized: "Last installment payment: \(lastTitle)", bundle: .module,
                        comment: "The argument is a month, e.g. May 2027"
                    ),
                    remaining: text,
                    monthsRemaining: remaining
                )
            }
            months = analytics.monthlyTotals(from: currentMonth, count: Self.monthCount)
            if !months.contains(where: { $0.month == selectedMonth }) { selectedMonth = currentMonth }
            state = months.allSatisfy { $0.total.isZero } ? .empty : .loaded
        } catch {
            // Hata sessizce boş grafik olmaz; ekranda hata durumu gösterilir.
            months = []
            analytics = nil
            insight = nil
            selectedMonth = currentMonth
            state = .error(message: Self.loadErrorMessage)
        }
    }

    /// The month as `"May 2026"` (same text as Home).
    public nonisolated static func title(of month: YearMonth) -> String {
        HomeViewModel.title(of: month)
    }

    /// The month's three-letter name for the chart axis: `"May"`.
    public nonisolated static func shortTitle(of month: YearMonth) -> String {
        VademLocalization.shortMonthTitle(month)
    }

    /// The bar as one VoiceOver label: `"May 2026, 4.250,00 TL"`.
    public nonisolated static func accessibilityLabel(for total: SpendingAnalytics.MonthTotal) -> String {
        let monthText = title(of: total.month)
        let amountText = AmountText.formattedMagnitude(total.total)
        return String(
            localized: "\(monthText), \(amountText) TL", bundle: .module,
            comment: "Spoken chart bar: month, amount"
        )
    }

    /// The bar chart's VoiceOver summary: what it shows, the total of `months` and the highest month,
    /// e.g. `"… Total: 24.000,00 TL. Highest: May 2026, 4.250,00 TL."`.
    ///
    /// Pure. Without months, or when every month is zero, only the first sentence is returned.
    /// Ties for the highest month go to the earlier month.
    public nonisolated static func chartSummary(for months: [SpendingAnalytics.MonthTotal]) -> String {
        let highest = months.reduce(nil as SpendingAnalytics.MonthTotal?) { best, total in
            guard let best, best.total >= total.total else { return total }
            return best
        }
        guard let highest, !highest.total.isZero else {
            return String(localized: "Installments and subscriptions due in each of the next 12 months", bundle: .module)
        }
        let totalText = AmountText.formattedMagnitude(months.reduce(Money.zero) { $0 + $1.total })
        let monthText = title(of: highest.month)
        let highestText = AmountText.formattedMagnitude(highest.total)
        return String(
            localized: "Installments and subscriptions due in each of the next 12 months. Total: \(totalText) TL. Highest: \(monthText), \(highestText) TL.",
            bundle: .module,
            comment: "Spoken chart summary: total of all months, highest month and its amount"
        )
    }

    /// A stable id for a month (`"2026-05"`), used as the chart's x value.
    public nonisolated static func id(of month: YearMonth) -> String {
        String(format: "%04d-%02d", month.year, month.month)
    }
}
