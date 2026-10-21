import SwiftUI
import VademCore

/// The Home screen: how much is due in the selected month, per card, and when.
///
/// The app's "Vadem" title and version label sit at the top, above the month.
/// No continuous animations, so it is idle under `-ui-static-motion`.
@MainActor
public struct HomeView: View {
    @State private var model: HomeViewModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates the screen for `model`.
    public init(model: HomeViewModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AppHeader()
                monthBar
                content
            }
            // 20 pt yan boşluk: ekranın sol kenarında her zaman arka plan rengi kalır.
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.vademBackground.ignoresSafeArea())
    }

    // Ay başlığı ve önceki/sonraki ay düğmeleri.
    private var monthBar: some View {
        HStack(spacing: 8) {
            monthButton(systemImage: "chevron.left", label: "Previous month", identifier: "home.previousMonth") {
                model.showPreviousMonth()
            }
            Text(model.monthTitle)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.vademTextPrimary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home.month")
            monthButton(systemImage: "chevron.right", label: "Next month", identifier: "home.nextMonth") {
                model.showNextMonth()
            }
        }
    }

    private func monthButton(
        systemImage: String, label: String, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.vademTextPrimary)
                // En az 44 pt dokunma alanı.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .error(let message):
            messageView(title: "Something went wrong", detail: message, systemImage: "exclamationmark.triangle")
                .accessibilityIdentifier("home.error")
        case .empty:
            totalSection
            messageView(title: "Nothing due this month", detail: nil, systemImage: "checkmark.circle")
                .accessibilityIdentifier("home.empty")
        case .loaded:
            totalSection
            if !model.cardSubtotals.isEmpty {
                subtotalsSection
            }
            listSection
        }
    }

    // Ayın toplamı; VoiceOver'da tek öğe ve başlık.
    private var totalSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Total due")
                .font(.headline)
                .foregroundStyle(Color.vademTextSecondary)
            AmountText(model.total)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Color.vademTextPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("home.total")
    }

    private var subtotalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("By card", identifier: "home.cards")
            ForEach(model.cardSubtotals) { subtotal in
                adaptiveStack {
                    Text(subtotal.name)
                        .font(.body)
                        .foregroundStyle(Color.vademTextPrimary)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    AmountText(subtotal.amount)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.vademTextPrimary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Payments", identifier: "home.list")
                .padding(.bottom, 8)
            ForEach(model.rows) { row in
                HomeRowView(row: row)
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.vademSeparator)
                            .frame(height: 1)
                            .accessibilityHidden(true)
                    }
            }
        }
    }

    // Bölüm başlığı; kimlik başlıkta, UI testi bu kimlikle kaydırır.
    private func sectionTitle(_ title: String, identifier: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color.vademTextSecondary)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
    }

    // Boş ve hata durumları için ortak görünüm.
    private func messageView(title: String, detail: String?, systemImage: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(Color.vademTextSecondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.vademTextPrimary)
            if let detail {
                Text(detail)
                    .font(.body)
                    .foregroundStyle(Color.vademTextSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
    }

    // Erişilebilir yazı boyutlarında yan yana yerine alt alta dizilir.
    private func adaptiveStack(@ViewBuilder content: () -> some View) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout(content)
    }
}

/// The "Vadem" title with the app version below it.
@MainActor
struct AppHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Vadem")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Color.vademTextPrimary)
                .accessibilityAddTraits(.isHeader)
            // Sürüm etiketi başlığın altında, daha küçük; ayrı erişilebilirlik etiketi yok.
            Text("Version \(VademCore.version)")
                .font(.subheadline)
                .foregroundStyle(Color.vademTextPrimary)
        }
    }
}

/// One payment: title, card, installment number, due day, amount and chip; read as one element.
@MainActor
struct HomeRowView: View {
    let row: HomeViewModel.Row

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.vademTextPrimary)
                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(Color.vademTextSecondary)
                Text("Due \(row.dueText)")
                    .font(.subheadline)
                    .foregroundStyle(Color.vademTextSecondary)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 6) {
                AmountText(row.amount)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.vademTextPrimary)
                DueChip(row.chipText, kind: row.chipKind)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Satır VoiceOver'da tek öğe; etiket view model'den gelir.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    // "Everyday card · 3/12" veya "No card".
    private var detailText: String {
        [row.cardText, row.installmentText].compactMap { $0 }.joined(separator: " · ")
    }
}

#if DEBUG
#Preview("Sample") {
    HomeView(model: HomeSampleData.makeViewModel())
}

#Preview("Empty") {
    HomeView(model: HomeViewModel(
        repository: InMemoryPaymentRepository(), today: HomeSampleData.today, calendar: HomeSampleData.calendar
    ))
}
#endif
