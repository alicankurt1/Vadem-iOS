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
                // Ay şeridi seçili ayın altında, listenin üstünde.
                if !model.upcoming.isEmpty {
                    UpcomingStrip(months: model.upcoming) { month in
                        model.select(month: month)
                    }
                }
                // Ay takvimi şeridin altında; bir güne dokunmak listeyi o güne süzer.
                if !model.calendarDays.isEmpty {
                    MonthCalendar(days: model.calendarDays, weekdaySymbols: model.calendarWeekdaySymbols) { day in
                        model.select(day: day)
                    }
                }
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
            if model.rows.isEmpty, let dayText = model.selectedDayText {
                // Seçili günde ödeme yok; ayın geri kalanı dolu olduğundan "bu ay boş" denmez.
                messageView(title: "Nothing due on \(dayText)", detail: nil, systemImage: "calendar")
                    .accessibilityIdentifier("home.dayEmpty")
                showAllButton
            } else {
                listSection
            }
        }
    }

    // Gün süzgecini kaldırır; tüm ayın ödemeleri yeniden listelenir.
    private var showAllButton: some View {
        Button {
            model.clearSelectedDay()
        } label: {
            Text("Show all payments")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.vademTextPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.showAll")
    }

    // Ayın toplamı; VoiceOver'da tek öğe ve başlık.
    private var totalSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Bölüm etiketleri koyu temada da kontrast denetimini geçsin diye birincil renkte;
            // hiyerarşi yazı boyutu ve ağırlığıyla kurulur.
            Text("Total due")
                .font(.headline)
                .foregroundStyle(Color.vademTextPrimary)
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
            sectionTitle(model.selectedDayText.map { "Payments on \($0)" } ?? "Payments", identifier: "home.list")
                .padding(.bottom, 8)
            if model.selectedDay != nil {
                showAllButton
                    .padding(.bottom, 8)
            }
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
            .foregroundStyle(Color.vademTextPrimary)
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

/// The upcoming months as a horizontal row of chips (month + total); tapping a chip selects it.
///
/// The selected chip is highlighted and scrolled into view (without animation under
/// Reduce Motion or `-ui-static-motion`). Identifier `home.upcoming`; chips are `home.upcoming.YYYY-MM`.
@MainActor
struct UpcomingStrip: View {
    let months: [HomeViewModel.MonthSummary]
    let select: (YearMonth) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Upcoming")
                .font(.headline)
                .foregroundStyle(Color.vademTextPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home.upcoming")
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(months) { summary in
                            chip(summary)
                                .id(summary.month)
                        }
                    }
                    // Seçili çipin çerçevesi kırpılmasın diye dikey pay.
                    .padding(.vertical, 2)
                }
                .onAppear { scrollToSelected(proxy, animated: false) }
                .onChange(of: selectedMonth) { scrollToSelected(proxy, animated: true) }
            }
        }
    }

    private var selectedMonth: YearMonth? {
        months.first(where: \.isSelected)?.month
    }

    private func chip(_ summary: HomeViewModel.MonthSummary) -> some View {
        Button {
            select(summary.month)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(.subheadline.weight(summary.isSelected ? .bold : .regular))
                AmountText(summary.total)
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(Color.vademTextPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // En az 44 pt dokunma alanı.
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .background(Color.vademSurface, in: .rect(cornerRadius: 12))
            .overlay {
                // Seçili ay kalın çerçeveyle ayrılır; renk tek başına anlam taşımaz (yazı da kalın).
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        summary.isSelected ? Color.vademTextPrimary : Color.vademSeparator,
                        lineWidth: summary.isSelected ? 2 : 1
                    )
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel)
        .accessibilityAddTraits(summary.isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("home.upcoming.\(Self.identifier(of: summary.month))")
    }

    private func scrollToSelected(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let selectedMonth else { return }
        let animation = animated ? Motion.animation(Motion.quick, reduceMotion: reduceMotion) : nil
        withAnimation(animation) {
            proxy.scrollTo(selectedMonth, anchor: .center)
        }
    }

    // "2026-11" biçiminde, UI testlerinde kararlı kimlik.
    private static func identifier(of month: YearMonth) -> String {
        "\(month.year)-\(month.month < 10 ? "0" : "")\(month.month)"
    }
}

/// The selected month as a grid; days with payments carry a dot, the selected day is filled
/// and today is outlined. Tapping a day (with or without payments) calls `select`.
///
/// Weeks start on the first weekday the view model was given. At accessibility text sizes the
/// days flow in wider cells that also name the weekday. No animations. Identifier `home.calendar`;
/// days are `home.calendar.day.<n>`.
@MainActor
struct MonthCalendar: View {
    let days: [HomeViewModel.CalendarDay]
    let weekdaySymbols: [String]
    let select: (Int) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calendar")
                .font(.headline)
                .foregroundStyle(Color.vademTextPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home.calendar")
            if dynamicTypeSize.isAccessibilitySize {
                accessibleGrid
            } else {
                weekGrid
            }
        }
    }

    // Yedi sütunlu klasik ay görünümü; gün başlıkları VoiceOver'da gizli (her gün kendi tarihini okur).
    private var weekGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.vademTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityHidden(true)
            }
            ForEach(days) { cell in
                if let day = cell.day {
                    dayButton(cell, day: day, showsWeekday: false)
                } else {
                    Color.clear
                        .frame(minHeight: 44)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    // Büyük yazıda yedi sütun sığmaz: boşluklar atlanır, her hücre gün adını da gösterir.
    private var accessibleGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(days.filter { $0.day != nil }) { cell in
                dayButton(cell, day: cell.day!, showsWeekday: true)
            }
        }
    }

    private func dayButton(_ cell: HomeViewModel.CalendarDay, day: Int, showsWeekday: Bool) -> some View {
        // Seçili gün ters renkli (dolgu birincil metin rengi), böylece iki temada da kontrast korunur.
        let foreground = cell.isSelected ? Color.vademBackground : Color.vademTextPrimary
        return Button {
            select(day)
        } label: {
            VStack(spacing: 2) {
                if showsWeekday {
                    Text(weekdaySymbols[cell.id % 7])
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                Text("\(day)")
                    .font(.body.weight(cell.hasPayments ? .bold : .regular))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                // Ödeme işareti nokta: renk tek başına anlam taşımaz (rakam da kalın).
                Circle()
                    .fill(cell.hasPayments ? (cell.isSelected ? Color.vademBackground : Color.vademBrand) : Color.clear)
                    .frame(width: 6, height: 6)
            }
            .foregroundStyle(foreground)
            .padding(.vertical, 4)
            // En az 44 pt dokunma alanı.
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(cell.isSelected ? Color.vademTextPrimary : Color.clear, in: .rect(cornerRadius: 10))
            .overlay {
                // Bugün çerçeveyle belirtilir.
                if cell.isToday {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.vademBrand, lineWidth: 2)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cell.accessibilityLabel)
        .accessibilityAddTraits(cell.isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("home.calendar.day.\(day)")
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
