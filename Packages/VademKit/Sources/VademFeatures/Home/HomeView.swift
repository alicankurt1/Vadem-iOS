import SwiftUI
import VademCore

/// The Home screen: how much is due in the selected month, per card, and when.
///
/// The app's "Vadem" title and version label sit at the top, above the month. Below the month
/// a ``HeroPanel`` shows the total and how much of it is due so far, with an "Add" menu
/// (`home.add`) and a "Calendar" pill (`home.showCalendar`) that scrolls to the month calendar.
/// Tapping a payment row (`home.row.<index>`) opens its form in edit mode; tapping a card
/// subtotal (`home.card.<index>`) opens the card's edit form. Home reloads when a form closes.
/// A gear button next to the title (`home.settings`) opens the ``SettingsView`` sheet.
/// On iOS 26+, a sparkles button next to Analytics (`home.assistant`) pushes the ``AssistantView``
/// unless ``HomeViewModel/showsAssistant`` is `false`.
/// No continuous animations, so it is idle under `-ui-static-motion`.
@MainActor
public struct HomeView: View {
    @State private var model: HomeViewModel
    // Açık ekleme formunun modeli; nil iken sayfa kapalı.
    @State private var addModel: AddInstallmentViewModel?
    // Açık kart formunun modeli; nil iken sayfa kapalı.
    @State private var addCardModel: AddCardViewModel?
    // Açık abonelik formunun modeli; nil iken sayfa kapalı.
    @State private var addSubscriptionModel: AddSubscriptionViewModel?
    // Açık ayarlar sayfasının modeli; nil iken sayfa kapalı.
    @State private var settingsModel: SettingsViewModel?
    // Açık Analytics ekranının modeli; nil iken ekran itilmemiştir.
    @State private var analyticsModel: AnalyticsViewModel?
    // Açık asistan ekranının modeli; nil iken ekran itilmemiştir. Kapanınca sohbet atılır.
    @State private var assistantModel: AssistantViewModel?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Takvim düğmesinin kaydırma hedefi.
    private static let calendarAnchor = "home.calendarAnchor"

    /// Creates the screen for `model`.
    ///
    /// In debug builds, ``AddInstallmentView/launchArgument`` opens the add form right away
    /// (with every error shown under ``AddInstallmentView/errorsLaunchArgument``), for the UI check.
    /// ``AddCardView/launchArgument`` does the same for the add-card form
    /// (errors: ``AddCardView/errorsLaunchArgument``), and ``AddSubscriptionView/launchArgument``
    /// for the add-subscription form (errors: ``AddSubscriptionView/errorsLaunchArgument``).
    /// ``AddInstallmentView/editLaunchArgument``, ``AddSubscriptionView/editLaunchArgument`` and
    /// ``AddCardView/editLaunchArgument`` open the first installment, subscription or card of the
    /// month in its edit form. ``SettingsView/launchArgument`` (or ``SettingsView/deniedLaunchArgument``)
    /// opens the settings sheet. ``AnalyticsView/launchArgument`` pushes the Analytics screen and
    /// ``AssistantView/launchArgument`` the assistant chat.
    public init(model: HomeViewModel) {
        _model = State(initialValue: model)
        var initialAddModel: AddInstallmentViewModel?
        var initialAddCardModel: AddCardViewModel?
        var initialAddSubscriptionModel: AddSubscriptionViewModel?
        var initialSettingsModel: SettingsViewModel?
        var initialAnalyticsModel: AnalyticsViewModel?
        var initialAssistantModel: AssistantViewModel?
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(AnalyticsView.launchArgument) {
            initialAnalyticsModel = model.makeAnalyticsModel()
        } else if arguments.contains(AssistantView.launchArgument) {
            // İki ekran aynı anda itilemez; Analytics önceliklidir.
            initialAssistantModel = model.makeAssistantModel()
        }
        if arguments.contains(AddInstallmentView.launchArgument) {
            let addModel = model.makeAddInstallmentModel()
            if arguments.contains(AddInstallmentView.errorsLaunchArgument) {
                addModel.showAllErrors()
            }
            initialAddModel = addModel
        } else if arguments.contains(AddCardView.launchArgument) {
            // İki sayfa aynı anda açılamaz; taksit formu önceliklidir.
            let addCardModel = model.makeAddCardModel()
            if arguments.contains(AddCardView.errorsLaunchArgument) {
                addCardModel.showAllErrors()
            }
            initialAddCardModel = addCardModel
        } else if arguments.contains(AddSubscriptionView.launchArgument) {
            let addSubscriptionModel = model.makeAddSubscriptionModel()
            if arguments.contains(AddSubscriptionView.errorsLaunchArgument) {
                addSubscriptionModel.showAllErrors()
            }
            initialAddSubscriptionModel = addSubscriptionModel
        } else if arguments.contains(AddInstallmentView.editLaunchArgument) {
            // Ayın ilk taksiti düzenleme modunda açılır.
            initialAddModel = model.rows.lazy
                .filter { $0.entry.kind != .subscription }
                .compactMap { model.makeEditInstallmentModel(id: $0.entry.itemID) }
                .first
        } else if arguments.contains(AddSubscriptionView.editLaunchArgument) {
            initialAddSubscriptionModel = model.rows.lazy
                .filter { $0.entry.kind == .subscription }
                .compactMap { model.makeEditSubscriptionModel(id: $0.entry.itemID) }
                .first
        } else if arguments.contains(AddCardView.editLaunchArgument) {
            initialAddCardModel = model.cardSubtotals.first.flatMap { model.makeEditCardModel(id: $0.id) }
        } else if arguments.contains(SettingsView.launchArgument)
                    || arguments.contains(SettingsView.deniedLaunchArgument) {
            initialSettingsModel = model.makeSettingsModel()
        }
        #endif
        _addModel = State(initialValue: initialAddModel)
        _addCardModel = State(initialValue: initialAddCardModel)
        _addSubscriptionModel = State(initialValue: initialAddSubscriptionModel)
        _settingsModel = State(initialValue: initialSettingsModel)
        _analyticsModel = State(initialValue: initialAnalyticsModel)
        _assistantModel = State(initialValue: initialAssistantModel)
    }

    public var body: some View {
        // NavigationStack çubuğu verir; içerik saatin altına girmez.
        NavigationStack {
            scrollContent
                .toolbar {
                    // Asistan düğmesi yalnızca iOS 26+ ve motor desteklenen bir sistemdeyken görünür.
                    if Self.isAssistantOS, model.showsAssistant {
                        ToolbarItem(placement: .primaryAction) { assistantButton }
                    }
                    ToolbarItem(placement: .primaryAction) { analyticsButton }
                }
                .navigationDestination(isPresented: assistantPresented) {
                    if let assistantModel {
                        AssistantView(model: assistantModel)
                    }
                }
                // Grafik ekranı itilir (sekme değil); geri düğmesi Home'a döner.
                .navigationDestination(isPresented: analyticsPresented) {
                    if let analyticsModel {
                        AnalyticsView(model: analyticsModel, onAddPayment: addPaymentFromAnalytics)
                    }
                }
                // Kart formu kapanınca Home yeniden yüklenir; yeni kart ve "kart ekle" girişi güncellenir.
                .sheet(item: $addCardModel, onDismiss: reloadAfterForm) { addCardModel in
                    AddCardView(model: addCardModel)
                }
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                // Galeri gibi: çubuk ekranın renk şemasına ve arka planına sabitlenir.
                .toolbarColorScheme(colorScheme, for: .navigationBar)
                .toolbarBackground(Color(Color.vademBackground.resolve(in: environment)), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                #endif
        }
        // Form kapanınca (kaydedilse de iptal edilse de) Home yeniden yüklenir; yeni ödeme hemen görünür.
        .sheet(item: $addModel, onDismiss: reloadAfterForm) { addModel in
            AddInstallmentView(model: addModel)
        }
        .sheet(item: $addSubscriptionModel, onDismiss: reloadAfterForm) { addSubscriptionModel in
            AddSubscriptionView(model: addSubscriptionModel)
        }
        // Ayarlar veriyi değiştirmez; zamanlayıcı her tercih değişikliğinde zaten yenilenir.
        .sheet(item: $settingsModel) { settingsModel in
            SettingsView(model: settingsModel)
        }
    }

    // Form kapanınca Home ve (açıksa) Analytics yeniden yüklenir.
    private func reloadAfterForm() {
        model.reloadAfterChange()
        analyticsModel?.reload()
    }

    private var analyticsPresented: Binding<Bool> {
        Binding(
            get: { analyticsModel != nil },
            set: { if !$0 { analyticsModel = nil } }
        )
    }

    private var assistantPresented: Binding<Bool> {
        Binding(
            get: { assistantModel != nil },
            set: { if !$0 { assistantModel = nil } }
        )
    }

    // Yerel model iOS 26 ile gelir; daha eski sistemde giriş hiç gösterilmez.
    private static var isAssistantOS: Bool {
        if #available(iOS 26, macOS 26, *) { return true }
        return false
    }

    // Araç çubuğundaki pırıltı düğmesi: asistan sohbetini açar.
    private var assistantButton: some View {
        Button {
            assistantModel = model.makeAssistantModel()
        } label: {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.vademTextPrimary)
                // En az 44 pt dokunma alanı.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("Assistant")
        .accessibilityIdentifier("home.assistant")
    }

    // Boş grafik ekranından ödeme ekleme: kart yoksa önce kart formu açılır. Sayfa Analytics'in üstünde açılır.
    private func addPaymentFromAnalytics() {
        if model.hasCards {
            addModel = model.makeAddInstallmentModel()
        } else {
            addCardModel = model.makeAddCardModel()
        }
    }

    // Araç çubuğundaki grafik düğmesi: Analytics ekranını açar.
    private var analyticsButton: some View {
        Button {
            analyticsModel = model.makeAnalyticsModel()
        } label: {
            Image(systemName: "chart.bar")
                .foregroundStyle(Color.vademTextPrimary)
                // En az 44 pt dokunma alanı.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("Analytics")
        .accessibilityIdentifier("home.analytics")
    }

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AppHeader { settingsButton }
                    monthBar
                    // Hata durumunda da görünür (toplam sıfır): ekleme menüsü her zaman erişilebilir.
                    hero(proxy)
                    sections
                }
                // 20 pt yan boşluk: ekranın sol kenarında her zaman arka plan rengi kalır.
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.vademBackground.ignoresSafeArea())
        }
    }

    // Ay şeridi ve takvim; hata durumunda ikisi de boş olduğundan görünmez.
    @ViewBuilder
    private var sections: some View {
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
            .id(Self.calendarAnchor)
        }
        content
    }

    // Ayın toplamı ve vadesi gelen kısmı; altında ekleme menüsü ve takvim düğmesi.
    private func hero(_ proxy: ScrollViewProxy) -> some View {
        HeroPanel(
            title: "Due this month", total: model.total, paid: model.dueSoFar,
            captionPrefix: "Due so far", summaryIdentifier: "home.total"
        ) {
            addMenu
            // Takvim gizliyken (hata durumu) kaydırılacak yer yok; düğme de gösterilmez.
            if !model.calendarDays.isEmpty {
                Button {
                    // Reduce Motion veya -ui-static-motion açıkken animasyonsuz kaydırır.
                    withAnimation(Motion.animation(Motion.quick, reduceMotion: reduceMotion)) {
                        proxy.scrollTo(Self.calendarAnchor, anchor: .top)
                    }
                } label: {
                    Label("Calendar", systemImage: "calendar")
                }
                .buttonStyle(.heroPill)
                .accessibilityIdentifier("home.showCalendar")
            }
        }
    }

    // "Add" bir menü: taksit mi abonelik mi eklenecek, kullanıcı seçer.
    // Menu düğme stili almadığından etiket hap görünümüyle elle biçimlenir.
    private var addMenu: some View {
        Menu {
            Button {
                addModel = model.makeAddInstallmentModel()
            } label: {
                Label("Installment", systemImage: "creditcard")
            }
            .accessibilityLabel("Add installment")
            .accessibilityIdentifier("home.add.installment")
            Button {
                addSubscriptionModel = model.makeAddSubscriptionModel()
            } label: {
                Label("Subscription", systemImage: "arrow.triangle.2.circlepath")
            }
            .accessibilityLabel("Add subscription")
            .accessibilityIdentifier("home.add.subscription")
        } label: {
            Label("Add", systemImage: "plus")
                .heroPillLabel()
        }
        .accessibilityLabel("Add payment")
        .accessibilityIdentifier("home.add")
    }

    // Başlığın yanındaki dişli: ayarlar sayfasını açar.
    private var settingsButton: some View {
        Button {
            settingsModel = model.makeSettingsModel()
        } label: {
            Image(systemName: "gearshape")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.vademTextPrimary)
                // En az 44 pt dokunma alanı.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("home.settings")
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
            if !model.hasCards { addCardPrompt }
            messageView(title: "Nothing due this month", detail: nil, systemImage: "checkmark.circle")
                .accessibilityIdentifier("home.empty")
        case .loaded:
            if !model.hasCards { addCardPrompt }
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

    // Hiç kart yokken taksit eklenemez; önce kart eklemeye yönlendirir.
    private var addCardPrompt: some View {
        SurfaceCard {
            addCardPromptContent
        }
    }

    private var addCardPromptContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a card to start tracking installments.")
                .font(.body)
                .foregroundStyle(Color.vademTextPrimary)
            Button {
                addCardModel = model.makeAddCardModel()
            } label: {
                Label("Add a card", systemImage: "plus.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.vademTextPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.addCard")
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

    private var subtotalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("By card", identifier: "home.cards")
            SurfaceCard {
                ForEach(Array(model.cardSubtotals.enumerated()), id: \.element.id) { index, subtotal in
                    // Alt toplama dokunmak kartın düzenleme formunu açar.
                    Button {
                        addCardModel = model.makeEditCardModel(id: subtotal.id)
                    } label: {
                        adaptiveStack {
                            Text(subtotal.name)
                                .font(.body)
                                .foregroundStyle(Color.vademTextPrimary)
                            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                            AmountText(subtotal.amount)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.vademTextPrimary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Edits the card")
                    .accessibilityIdentifier("home.card.\(index)")
                }
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
            SurfaceCard {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    // Satıra dokunmak ödemenin formunu düzenleme modunda açar; VoiceOver etiketi aynı kalır.
                    Button {
                        edit(row)
                    } label: {
                        HomeRowView(row: row)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edits the payment")
                    .accessibilityIdentifier("home.row.\(index)")
                }
            }
        }
    }

    // Satırın kalemine göre taksit ya da abonelik formu düzenleme modunda açılır.
    private func edit(_ row: HomeViewModel.Row) {
        switch row.entry.kind {
        case .installment:
            addModel = model.makeEditInstallmentModel(id: row.entry.itemID)
        case .subscription:
            addSubscriptionModel = model.makeEditSubscriptionModel(id: row.entry.itemID)
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
                    // Seçili çipte tutar ikincil hero rengiyle (hero üzerinde kontrastı testle güvencede).
                    .foregroundStyle(summary.isSelected ? Color.vademHeroSecondary : Color.vademTextPrimary)
            }
            // Seçili çip koyu hero zeminde açık yazıyla; seçili olmayan yüzey zeminde birincil metin.
            .foregroundStyle(summary.isSelected ? Color.vademHeroText : Color.vademTextPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // En az 44 pt dokunma alanı.
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .background(
                summary.isSelected ? Color.vademHero : Color.vademSurface,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                // Seçili olmayan çipte ince ayırıcı çerçeve; seçili ay dolgu ve kalın yazıyla ayrılır
                // (renk tek başına anlam taşımaz).
                if !summary.isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.vademSeparator, lineWidth: 1)
                }
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
            // Izgara yuvarlak köşeli yüzey kartında (çerçevesiz). Yedi sütunlu görünümde yan pay
            // 2 pt, sütun arası 2 pt: 375 pt genişlikteki iPhone'larda (SE, mini) bile her sütun
            // 44 pt'nin üstünde kalır (375 - 2×20 sayfa payı - 2×2 kart payı - 6×2 aralık = 319 → 7 × ~45.6 pt).
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    accessibleGrid
                } else {
                    weekGrid
                }
            }
            .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 8 : 2)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.vademSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // Yedi sütunlu klasik ay görünümü; gün başlıkları VoiceOver'da gizli (her gün kendi tarihini okur).
    private var weekGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.vademTextSecondary)
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
            ForEach(days) { cell in
                // Boş hücreler (ay öncesi dolgu) bu görünümde atlanır.
                if let day = cell.day {
                    dayButton(cell, day: day, showsWeekday: true)
                }
            }
        }
    }

    private func dayButton(_ cell: HomeViewModel.CalendarDay, day: Int, showsWeekday: Bool) -> some View {
        // Seçili gün hero dolgulu, açık yazılı; iki temada da kontrast hero çiftiyle korunur.
        let foreground = cell.isSelected ? Color.vademHeroText : Color.vademTextPrimary
        // Normal ızgarada gün daire; büyük yazıda hücre uzun olduğundan yuvarlak köşeli kutu.
        let shape = showsWeekday
            ? AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            : AnyShape(Circle())
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
                    .fill(cell.hasPayments ? (cell.isSelected ? Color.vademHeroText : Color.vademBrand) : Color.clear)
                    .frame(width: 6, height: 6)
            }
            .foregroundStyle(foreground)
            .padding(.vertical, 4)
            // En az 44 pt dokunma alanı.
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if cell.isSelected {
                    shape.fill(Color.vademHero)
                }
            }
            .overlay {
                // Bugün marka renginde halkayla belirtilir.
                if cell.isToday {
                    // AnyShape içe çizim desteklemez; yarım çizgi kalınlığı kadar içeri alınır.
                    shape.stroke(Color.vademBrand, lineWidth: 2)
                        .padding(1)
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

/// The "Vadem" title with the app version below it; `trailing` (e.g. a button) sits on the title's line.
@MainActor
struct AppHeader<Trailing: View>: View {
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Sağdaki öğe yalnızca başlık satırında; sürüm etiketi tüm genişliği kullanır.
            HStack(alignment: .center, spacing: 8) {
                Text("Vadem")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.vademTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                trailing
            }
            // Sürüm etiketi başlığın altında, daha küçük; ayrı erişilebilirlik etiketi yok.
            Text("Version \(VademCore.version)")
                .font(.subheadline)
                .foregroundStyle(Color.vademTextPrimary)
        }
    }
}

extension AppHeader where Trailing == EmptyView {
    /// The header without a trailing item.
    init() {
        self.init { EmptyView() }
    }
}

/// One payment as a ``PaymentRow`` (due day, title, "card · n/m", amount, chip), read as one
/// element with the view model's label.
@MainActor
struct HomeRowView: View {
    let row: HomeViewModel.Row

    var body: some View {
        PaymentRow(
            day: row.entry.dueDate.day,
            title: row.title,
            subtitle: detailText,
            amount: row.amount,
            dueTitle: row.chipText,
            dueKind: row.chipKind
        )
        // Satır VoiceOver'da tek öğe; etiket view model'den gelir (PaymentRow'un etiketinin yerine).
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
