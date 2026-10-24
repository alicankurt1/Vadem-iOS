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

    /// The number of months the chart shows.
    public nonisolated static let monthCount = 12
    /// The message of the ``State/error(message:)`` state.
    public nonisolated static let loadErrorMessage = "Your payments could not be loaded."

    /// The current state.
    public private(set) var state: State = .loading
    /// ``monthCount`` consecutive totals starting with ``currentMonth``; empty before loading and after an error.
    public private(set) var months: [SpendingAnalytics.MonthTotal] = []
    /// The month whose ``summary`` is shown; starts as ``currentMonth``.
    public private(set) var selectedMonth: YearMonth
    /// The month that contains the injected today.
    public let currentMonth: YearMonth

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

    /// Selects `month` for the summary; a month that is not one of ``months`` is ignored.
    public func select(month: YearMonth) {
        guard months.contains(where: { $0.month == month }) else { return }
        selectedMonth = month
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
            months = analytics.monthlyTotals(from: currentMonth, count: Self.monthCount)
            if !months.contains(where: { $0.month == selectedMonth }) { selectedMonth = currentMonth }
            state = months.allSatisfy { $0.total.isZero } ? .empty : .loaded
        } catch {
            // Hata sessizce boş grafik olmaz; ekranda hata durumu gösterilir.
            months = []
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
        String(HomeViewModel.title(of: month).prefix(3))
    }

    /// The bar as one VoiceOver label: `"May 2026, 4.250,00 TL"`.
    public nonisolated static func accessibilityLabel(for total: SpendingAnalytics.MonthTotal) -> String {
        "\(title(of: total.month)), \(AmountText.formattedMagnitude(total.total)) TL"
    }

    /// A stable id for a month (`"2026-05"`), used as the chart's x value.
    public nonisolated static func id(of month: YearMonth) -> String {
        String(format: "%04d-%02d", month.year, month.month)
    }
}
