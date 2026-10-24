import Accessibility
import Charts
import SwiftUI
import VademCore

/// The Analytics screen: a stacked bar chart of the next 12 months (installments vs subscriptions).
///
/// A summary card (`analytics.summary`) above the chart (`analytics.chart`) shows the selected
/// month; selecting a bar changes it. The current month is highlighted. Without data the screen shows
/// an empty state (`analytics.empty`) with an "Add a payment" button (`analytics.addPayment`)
/// that calls `onAddPayment`. The chart does not animate under Reduce Motion or `-ui-static-motion`.
@MainActor
public struct AnalyticsView: View {
    /// The launch argument that opens Home with the Analytics screen already pushed (debug builds).
    public nonisolated static let launchArgument = "-ui-analytics"

    private static let installmentsName = "Installments"
    private static let subscriptionsName = "Subscriptions"

    @State private var model: AnalyticsViewModel
    // Grafikte seçili ayın kimliği; nil = seçim yok (özet son seçili ayı gösterir).
    @State private var chartSelection: String?
    private let onAddPayment: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment

    /// Creates the screen for `model`; `onAddPayment` is the empty state's "Add a payment" action
    /// (the button is hidden when it is `nil`).
    public init(model: AnalyticsViewModel, onAddPayment: (() -> Void)? = nil) {
        _model = State(initialValue: model)
        self.onAddPayment = onAddPayment
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.vademBackground.ignoresSafeArea())
        .navigationTitle("Analytics")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        // Home gibi: çubuk ekranın renk şemasına ve arka planına sabitlenir.
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .toolbarBackground(Color(Color.vademBackground.resolve(in: environment)), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
        // Ekran her açıldığında (ve form kapanınca Home'dan) veri yenilenir.
        .onAppear { model.reload() }
        .accessibilityIdentifier("analytics.screen")
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .accessibilityIdentifier("analytics.loading")
        case .error(let message):
            messageView(title: "Something went wrong", detail: message, systemImage: "exclamationmark.triangle")
                .accessibilityIdentifier("analytics.error")
        case .empty:
            messageView(
                title: "No payments yet", detail: "Add a payment to see your next 12 months.",
                systemImage: "chart.bar"
            )
            .accessibilityIdentifier("analytics.empty")
            if let onAddPayment {
                Button(action: onAddPayment) {
                    Label("Add a payment", systemImage: "plus.circle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.vademTextPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("analytics.addPayment")
            }
        case .loaded:
            if let summary = model.summary {
                summaryCard(summary)
            }
            chart
        }
    }

    // Seçili ayın toplamı ve iki parçası.
    private func summaryCard(_ summary: AnalyticsViewModel.Summary) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.title)
                    .font(.subheadline)
                    .foregroundStyle(Color.vademTextSecondary)
                AmountText(summary.total)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.vademTextPrimary)
            }
            partRow("Installments", amount: summary.installments, color: .vademBrand)
            partRow("Subscriptions", amount: summary.subscriptions, color: .vademAccent)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("analytics.summary")
    }

    private func partRow(_ title: LocalizedStringKey, amount: Money, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
            Text(title).foregroundStyle(Color.vademTextPrimary)
            Spacer(minLength: 8)
            AmountText(amount).foregroundStyle(Color.vademTextPrimary)
        }
        .font(.body)
    }

    private var chart: some View {
        Chart {
            ForEach(model.months, id: \.month) { total in
                let id = AnalyticsViewModel.id(of: total.month)
                let label = AnalyticsViewModel.accessibilityLabel(for: total)
                let opacity = Self.opacity(for: total.month, in: model)
                // Grafik değerleri için Double kaçınılmaz; gösterilen metinler Decimal'den gelir.
                BarMark(x: .value("Month", id), y: .value("Amount", Self.value(total.installments)))
                    .foregroundStyle(by: .value("Kind", Self.installmentsName))
                    .opacity(opacity)
                    .accessibilityLabel(label)
                    .accessibilityValue("\(Self.installmentsName) \(AmountText.formattedMagnitude(total.installments)) TL")
                BarMark(x: .value("Month", id), y: .value("Amount", Self.value(total.subscriptions)))
                    .foregroundStyle(by: .value("Kind", Self.subscriptionsName))
                    .opacity(opacity)
                    .accessibilityLabel(label)
                    .accessibilityValue("\(Self.subscriptionsName) \(AmountText.formattedMagnitude(total.subscriptions)) TL")
            }
        }
        .chartForegroundStyleScale([
            Self.installmentsName: Color.vademBrand,
            Self.subscriptionsName: Color.vademAccent,
        ])
        .chartXSelection(value: $chartSelection)
        .chartXAxis {
            AxisMarks(values: model.months.map { AnalyticsViewModel.id(of: $0.month) }) { value in
                AxisValueLabel {
                    if let id = value.as(String.self), let month = model.months.first(where: {
                        AnalyticsViewModel.id(of: $0.month) == id
                    })?.month {
                        Text(AnalyticsViewModel.shortTitle(of: month))
                            .font(.caption2)
                            .fontWeight(month == model.currentMonth ? .bold : .regular)
                            .foregroundStyle(Color.vademTextPrimary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color.vademSeparator)
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(Self.axisText(amount)).font(.caption2).foregroundStyle(Color.vademTextSecondary)
                    }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 280)
        .onChange(of: chartSelection) { _, id in
            // Seçim kalkınca (dokunuş bitince) özet son seçili ayda kalır.
            guard let id, let month = model.months.first(where: { AnalyticsViewModel.id(of: $0.month) == id })?.month
            else { return }
            model.select(month: month)
        }
        // Reduce Motion / -ui-static-motion açıkken veri değişimi animasyonsuz çizilir.
        .animation(Motion.animation(Motion.amount, reduceMotion: reduceMotion), value: model.months)
        .accessibilityChartDescriptor(AnalyticsChartDescriptor(months: model.months))
        .accessibilityIdentifier("analytics.chart")
    }

    // Seçili ve bu ay tam opak; diğerleri soluk.
    private static func opacity(for month: YearMonth, in model: AnalyticsViewModel) -> Double {
        month == model.selectedMonth || month == model.currentMonth ? 1 : 0.5
    }

    fileprivate nonisolated static func value(_ money: Money) -> Double {
        NSDecimalNumber(decimal: money.amount).doubleValue
    }

    // Eksen etiketi kısa: 1500 → "1,5B" yerine tam sayı lira; yer kazanmak için binlik "k".
    private static func axisText(_ amount: Double) -> String {
        amount >= 1000 ? "\(Int((amount / 1000).rounded()))k" : "\(Int(amount))"
    }

    private func messageView(title: String, detail: String?, systemImage: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(Color.vademTextSecondary)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(title))
                .font(.headline)
                .foregroundStyle(Color.vademTextPrimary)
            if let detail {
                Text(LocalizedStringKey(detail))
                    .font(.body)
                    .foregroundStyle(Color.vademTextSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
    }
}

// VoiceOver için grafiğin sesli/dokunsal özeti: ay ekseni ve iki serinin tutarları.
private struct AnalyticsChartDescriptor: AXChartDescriptorRepresentable {
    let months: [SpendingAnalytics.MonthTotal]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Month", categoryOrder: months.map { AnalyticsViewModel.title(of: $0.month) }
        )
        let top = months.map { AnalyticsView.value($0.total) }.max() ?? 0
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Amount (TL)", range: 0...max(top, 1), gridlinePositions: []
        ) { value in
            AmountText.formattedMagnitude(Money(Decimal(value))) + " TL"
        }
        func series(_ name: String, _ part: (SpendingAnalytics.MonthTotal) -> Money) -> AXDataSeriesDescriptor {
            AXDataSeriesDescriptor(
                name: name, isContinuous: false,
                dataPoints: months.map {
                    AXDataPoint(x: AnalyticsViewModel.title(of: $0.month), y: AnalyticsView.value(part($0)))
                }
            )
        }
        return AXChartDescriptor(
            title: "Monthly payments", summary: "Installments and subscriptions due in each of the next 12 months",
            xAxis: xAxis, yAxis: yAxis, additionalAxes: [],
            series: [series("Installments", \.installments), series("Subscriptions", \.subscriptions)]
        )
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        let updated = makeChartDescriptor()
        descriptor.series = updated.series
        descriptor.xAxis = updated.xAxis
        descriptor.yAxis = updated.yAxis
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        AnalyticsView(model: AnalyticsViewModel(
            repository: HomeSampleData.makeRepository(), today: HomeSampleData.today, calendar: HomeSampleData.calendar
        ))
    }
}
#endif
