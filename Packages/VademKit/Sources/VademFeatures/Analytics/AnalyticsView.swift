import Accessibility
import Charts
import SwiftUI
import VademCore

/// The Analytics screen: a stacked bar chart of the next 12 months (installments, subscriptions
/// and one-time payments).
///
/// A summary card (`analytics.summary`) above the chart (`analytics.chart`) shows the selected
/// month; selecting a bar changes it (with VoiceOver, swiping up or down on the summary does).
/// The chart's VoiceOver summary names the 12-month total and the highest month. The current
/// month is highlighted. Without data the screen shows an empty state (`analytics.empty`) with an
/// "Add a payment" button (`analytics.addPayment`) that calls `onAddPayment`. The chart does not
/// animate under Reduce Motion or `-ui-static-motion`.
@MainActor
public struct AnalyticsView: View {
    /// The launch argument that opens the app on the Analytics tab (debug builds).
    public nonisolated static let launchArgument = "-ui-analytics"

    // Seri adları lejantta görünür; katalogdan gelir.
    fileprivate nonisolated static var installmentsName: String { String(localized: "Installments", bundle: .module) }
    fileprivate nonisolated static var subscriptionsName: String { String(localized: "Subscriptions", bundle: .module) }
    fileprivate nonisolated static var oneTimePaymentsName: String {
        String(localized: "One-time payments", bundle: .module)
    }
    // Grafik değerlerinin adları (Swift Charts erişilebilirliği için).
    private static var monthLabel: String { String(localized: "Month", bundle: .module) }
    private static var amountLabel: String { String(localized: "Amount", bundle: .module) }
    private static var kindLabel: String { String(localized: "Kind", bundle: .module) }

    @State private var model: AnalyticsViewModel
    // Grafikte seçili ayın kimliği; nil = seçim yok (özet son seçili ayı gösterir).
    @State private var chartSelection: String?
    private let onAddPayment: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment
    // Sütunlar ilk görünüşte sıfırdan dolar; hareket kapalıyken baştan tam çizilir.
    @State private var barsHaveAppeared = false

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
            // Giriş yalnızca sekmenin ilk görünüşünde; sonradan oluşan görünümler doğrudan görünür.
            .motionEntryScope()
        }
        .navigationTitle(Text("Analytics", bundle: .module))
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
            messageView(title: Text("Something went wrong", bundle: .module), detail: Text(message), systemImage: "exclamationmark.triangle")
                .accessibilityIdentifier("analytics.error")
        case .empty:
            messageView(
                title: Text("No payments yet", bundle: .module),
                detail: Text("Add a payment to see your next 12 months.", bundle: .module),
                systemImage: "chart.bar"
            )
            .accessibilityIdentifier("analytics.empty")
            if let onAddPayment {
                Button(action: onAddPayment) {
                    Label { Text("Add a payment", bundle: .module) } icon: { Image(systemName: "plus.circle") }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.vademTextPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("analytics.addPayment")
            }
        case .loaded:
            // İlk görünüşte kademeli giriş: önce özet, sonra grafik, sonra dağılım.
            if let summary = model.summary {
                summaryCard(summary)
                    .motionEntry(order: .header)
            }
            chart
                .motionEntry(order: .hero)
            breakdown
                .motionEntry(order: .list)
            if let insight = model.insight {
                insightCard(insight)
                    .motionEntry(order: .list)
            }
        }
    }

    // Seçili ayın kart dağılımı: halka grafik ve altında açıklama satırları.
    @ViewBuilder
    private var breakdown: some View {
        let shares = model.cardShares
        SurfaceCard {
            Text("By card", bundle: .module)
                .font(.headline)
                .foregroundStyle(Color.vademTextPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("analytics.breakdown")
            if shares.isEmpty {
                Text("Nothing is due this month.", bundle: .module)
                    .font(.body)
                    .foregroundStyle(Color.vademTextSecondary)
                    .accessibilityIdentifier("analytics.donut.empty")
            } else {
                donut(shares)
                legend(shares)
            }
        }
    }

    private func donut(_ shares: [AnalyticsViewModel.CardShareRow]) -> some View {
        Chart(shares) { share in
            SectorMark(
                angle: .value(Self.amountLabel, Self.value(share.amount)),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .foregroundStyle(Self.color(of: share))
        }
        .chartLegend(.hidden)
        .frame(height: 220)
        .animation(Motion.animation(Motion.amount, reduceMotion: reduceMotion), value: shares)
        // Küçük dilimler 44 pt altı ayrı öğeler olmasın: halka tek öğe, ayrıntılar açıklama satırlarında.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Self.donutLabel(shares)
        )
        .accessibilityIdentifier("analytics.donut")
    }

    private func legend(_ shares: [AnalyticsViewModel.CardShareRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(shares) { share in
                // En büyük yazı boyutunda satır dikey dizilir; metin kırpılmaz.
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                layout {
                    HStack(spacing: 8) {
                        Circle().fill(Self.color(of: share)).frame(width: 10, height: 10).accessibilityHidden(true)
                        Text(share.name).foregroundStyle(Color.vademTextPrimary)
                    }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                        AmountText(share.amount).foregroundStyle(Color.vademTextPrimary)
                        Text("\(share.percent)%", bundle: .module).font(.subheadline).foregroundStyle(Color.vademTextSecondary)
                    }
                }
                .font(.body)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(share.accessibilityLabel)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("analytics.legend")
    }

    // Halkanın tek VoiceOver etiketi: "Spending by card: Night, 1.200,00 TL, 40 percent; …".
    private static func donutLabel(_ shares: [AnalyticsViewModel.CardShareRow]) -> String {
        let list = shares.map(\.accessibilityLabel).joined(separator: "; ")
        return String(localized: "Spending by card: \(list)", bundle: .module, comment: "The argument lists every card share")
    }

    // Kartın kendi stilinin orta mesh rengi; kartsız ödemeler nötr renkte.
    private static func color(of share: AnalyticsViewModel.CardShareRow) -> Color {
        share.style.map { $0.meshColors[4] } ?? .vademTextSecondary
    }

    // Son taksit ödemesi ve kalan ay sayısı.
    private func insightCard(_ insight: AnalyticsViewModel.Insight) -> some View {
        SurfaceCard {
            Text(insight.title)
                .font(.headline)
                .foregroundStyle(Color.vademTextPrimary)
            Text(insight.remaining)
                .font(.body)
                .foregroundStyle(Color.vademTextSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("analytics.insight")
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
            partRow("One-time payments", amount: summary.oneTimePayments, color: Self.oneTimeColor)
        }
        .accessibilityElement(children: .combine)
        // Grafikte dokunarak seçim VoiceOver'da yapılamaz: özet kartı ayarlanabilir öğe,
        // yukarı/aşağı kaydırma ayı değiştirir (halka ve açıklama satırları da güncellenir).
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.selectMonth(offsetBy: 1)
            case .decrement: model.selectMonth(offsetBy: -1)
            @unknown default: break
            }
        }
        .accessibilityHint(Text("Swipe up or down to change the month", bundle: .module))
        .accessibilityIdentifier("analytics.summary")
    }

    // Başlık anahtarla çizilir (Text(String) değil): yerelleştirilmiş metin uzun sözcükleri tireyle böler;
    // AX5'te düz metin harf harf kırılıyor ve düzen kayıyordu.
    private func partRow(_ title: LocalizedStringKey, amount: Money, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
            Text(title, bundle: .module).foregroundStyle(Color.vademTextPrimary)
            Spacer(minLength: 8)
            AmountText(amount).foregroundStyle(Color.vademTextPrimary)
        }
        .font(.body)
    }

    // Lejant grafiğin sabit yüksekliğinin dışında: büyük yazıda satırlara sarılırken dikeyde kırpılmaz.
    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            barChart
            chartLegend
        }
    }

    private var barChart: some View {
        let isAnimated = Motion.isAnimated(reduceMotion: reduceMotion, staticMotionRequested: Motion.staticMotionRequested)
        // Doluluk çarpanı: ilk görünüşte 0'dan 1'e; okunan değerler Decimal'den gelir, etkilenmez.
        let fill = Motion.fillFraction(1, hasAppeared: barsHaveAppeared, isAnimated: isAnimated)
        // Eksen tam değerlere göre kalır; yoksa sütunlarla birlikte ölçeklenip dolum görünmezdi.
        let fullMaximum = model.months.map {
            Self.value($0.installments) + Self.value($0.subscriptions) + Self.value($0.oneTimePayments)
        }.max() ?? 0
        return Chart {
            ForEach(model.months, id: \.month) { total in
                let id = AnalyticsViewModel.id(of: total.month)
                let label = AnalyticsViewModel.accessibilityLabel(for: total)
                let opacity = Self.opacity(for: total.month, in: model)
                // Grafik değerleri için Double kaçınılmaz; gösterilen metinler Decimal'den gelir.
                BarMark(x: .value(Self.monthLabel, id), y: .value(Self.amountLabel, Self.value(total.installments) * fill))
                    .foregroundStyle(by: .value(Self.kindLabel, Self.installmentsName))
                    .opacity(opacity)
                    .accessibilityLabel(label)
                    .accessibilityValue(Self.partValue(Self.installmentsName, total.installments))
                BarMark(x: .value(Self.monthLabel, id), y: .value(Self.amountLabel, Self.value(total.subscriptions) * fill))
                    .foregroundStyle(by: .value(Self.kindLabel, Self.subscriptionsName))
                    .opacity(opacity)
                    .accessibilityLabel(label)
                    .accessibilityValue(Self.partValue(Self.subscriptionsName, total.subscriptions))
                BarMark(x: .value(Self.monthLabel, id), y: .value(Self.amountLabel, Self.value(total.oneTimePayments) * fill))
                    .foregroundStyle(by: .value(Self.kindLabel, Self.oneTimePaymentsName))
                    .opacity(opacity)
                    .accessibilityLabel(label)
                    .accessibilityValue(Self.partValue(Self.oneTimePaymentsName, total.oneTimePayments))
            }
        }
        .chartForegroundStyleScale([
            Self.installmentsName: Color.vademBrand,
            Self.subscriptionsName: Color.vademAccent,
            Self.oneTimePaymentsName: Self.oneTimeColor,
        ])
        .chartYScale(domain: .automatic(dataType: Double.self) { $0.append(fullMaximum) })
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
        // Hazır lejant sistem ikincil grisiyle çiziliyordu (açık zeminde ~3.3:1); kendi lejantımız grafiğin altında.
        .chartLegend(.hidden)
        .frame(height: 280)
        .onChange(of: chartSelection) { _, id in
            // Seçim kalkınca (dokunuş bitince) özet son seçili ayda kalır.
            guard let id, let month = model.months.first(where: { AnalyticsViewModel.id(of: $0.month) == id })?.month
            else { return }
            model.select(month: month)
        }
        // Reduce Motion / -ui-static-motion açıkken veri değişimi animasyonsuz çizilir.
        .animation(Motion.animation(Motion.amount, reduceMotion: reduceMotion), value: model.months)
        .onAppear {
            guard !barsHaveAppeared else { return }
            withAnimation(Motion.animation(Motion.fill, reduceMotion: reduceMotion)) { barsHaveAppeared = true }
        }
        .accessibilityChartDescriptor(AnalyticsChartDescriptor(months: model.months))
        .accessibilityIdentifier("analytics.chart")
    }

    // Grafiğin lejantı: seri adları vademTextSecondary ile (vademBackground üzerinde kontrastı testle güvencede).
    // Sığmayan öğeler alt satıra geçer, uzun ad birden çok satıra kırılır; metin kırpılmaz.
    private var chartLegend: some View {
        FlowLayout(horizontalSpacing: 12, verticalSpacing: 4) {
            legendItem(Self.installmentsName, color: .vademBrand)
            legendItem(Self.subscriptionsName, color: .vademAccent)
            legendItem(Self.oneTimePaymentsName, color: Self.oneTimeColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Tek seferlik ödemelerin seri rengi; taksit ve abonelik renklerinden ayrışan mevcut bir token.
    private static var oneTimeColor: Color { .vademDueSoon }

    private func legendItem(_ name: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(name)
                .font(.footnote)
                .foregroundStyle(Color.vademTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Çubuğun okunan değeri: "Installments 1.200,00 TL".
    private static func partValue(_ name: String, _ amount: Money) -> String {
        let amountText = AmountText.formattedMagnitude(amount)
        return String(localized: "\(name) \(amountText) TL", bundle: .module, comment: "Spoken bar part: series name, amount")
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
        guard amount >= 1000 else { return "\(Int(amount))" }
        let thousands = Int((amount / 1000).rounded())
        return String(localized: "\(thousands)k", bundle: .module, comment: "Chart axis label in thousands, e.g. 5k")
    }

    // Metinler hazır Text olarak gelir: katalog anahtarıyla kurulan Text tireleme yapar (bkz. partRow).
    private func messageView(title: Text, detail: Text?, systemImage: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(Color.vademTextSecondary)
                .accessibilityHidden(true)
            title
                .font(.headline)
                .foregroundStyle(Color.vademTextPrimary)
            if let detail {
                detail
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

// VoiceOver için grafiğin sesli/dokunsal özeti (Audio Graph): ay ekseni, iki serinin tutarları
// ve metin özeti (12 ayın toplamı, en yüksek ay).
private struct AnalyticsChartDescriptor: AXChartDescriptorRepresentable {
    let months: [SpendingAnalytics.MonthTotal]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: String(localized: "Month", bundle: .module), categoryOrder: months.map { AnalyticsViewModel.title(of: $0.month) }
        )
        let top = months.map { AnalyticsView.value($0.total) }.max() ?? 0
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Amount (TL)", bundle: .module), range: 0...max(top, 1), gridlinePositions: []
        ) { value in
            let amountText = AmountText.formattedMagnitude(Money(Decimal(value)))
            return String(localized: "\(amountText) TL", bundle: .module, comment: "Spoken axis value in lira")
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
            title: String(localized: "Monthly payments", bundle: .module),
            summary: AnalyticsViewModel.chartSummary(for: months),
            xAxis: xAxis, yAxis: yAxis, additionalAxes: [],
            series: [
                series(AnalyticsView.installmentsName, \.installments),
                series(AnalyticsView.subscriptionsName, \.subscriptions),
                series(AnalyticsView.oneTimePaymentsName, \.oneTimePayments),
            ]
        )
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        let updated = makeChartDescriptor()
        // Özet de verilerle değişir (toplam ve en yüksek ay).
        descriptor.summary = updated.summary
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
