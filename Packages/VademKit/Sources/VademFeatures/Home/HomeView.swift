import SwiftUI
import VademCore

/// The Home screen ("This month" tab of the ``AppTabShell``): how much is due in the selected month,
/// per card, and when.
///
/// Shown inside the shell's `NavigationStack` (the "Vadem" title is in its bar). Below the month
/// a ``HeroPanel`` shows the total and how much of it is due so far, with an "Add" button
/// (`home.add`, shown when `onAdd` is given) that calls `onAdd` (the shell opens the ``AddFlowSheet``)
/// and a "Calendar" pill (`home.showCalendar`) that scrolls to the month calendar.
/// Tapping a payment row (`home.row.<index>`) opens its form in edit mode (a one-time payment opens the
/// ``EditOneTimePaymentView``); tapping a card subtotal (`home.card.<index>`) opens the card's edit form.
/// When a form closes, `onDataChanged` runs (``HomeViewModel/reloadAfterChange()`` when `nil`).
/// On iOS 26+, a sparkles button (`home.assistant`) pushes the ``AssistantView``
/// unless ``HomeViewModel/showsAssistant`` is `false`.
/// No continuous animations, so it is idle under `-ui-static-motion`.
@MainActor
public struct HomeView: View {
    @State private var model: HomeViewModel
    // Açık taksit düzenleme formunun modeli; nil iken sayfa kapalı.
    @State private var addModel: AddInstallmentViewModel?
    // Açık kart formunun modeli (ekleme veya düzenleme); nil iken sayfa kapalı.
    @State private var addCardModel: AddCardViewModel?
    // Açık abonelik düzenleme formunun modeli; nil iken sayfa kapalı.
    @State private var addSubscriptionModel: AddSubscriptionViewModel?
    // Açık tek seferlik ödeme düzenleme formunun modeli; nil iken sayfa kapalı.
    @State private var editOneTimeModel: EditOneTimePaymentViewModel?
    // Açık asistan ekranının modeli; nil iken ekran itilmemiştir. Kapanınca sohbet atılır.
    @State private var assistantModel: AssistantViewModel?
    private let onAdd: (() -> Void)?
    private let onDataChanged: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Takvim düğmesinin kaydırma hedefi.
    private static let calendarAnchor = "home.calendarAnchor"

    /// Creates the screen for `model`; `onAdd` is the hero's "Add" action (hidden when `nil`) and
    /// `onDataChanged` runs when a form closes (``HomeViewModel/reloadAfterChange()`` when `nil`).
    ///
    /// In debug builds, ``AddInstallmentView/editLaunchArgument``, ``AddSubscriptionView/editLaunchArgument``
    /// and ``AddCardView/editLaunchArgument`` open the first installment, subscription or card of the
    /// month in its edit form, ``EditOneTimePaymentView/editLaunchArgument`` (`-ui-edit-onetime`) the
    /// first saved one-time payment, and ``AssistantView/launchArgument`` pushes the assistant chat.
    /// The add forms and flows are opened by the ``AppTabShell``.
    public init(model: HomeViewModel, onAdd: (() -> Void)? = nil, onDataChanged: (() -> Void)? = nil) {
        _model = State(initialValue: model)
        self.onAdd = onAdd
        self.onDataChanged = onDataChanged
        var initialAddModel: AddInstallmentViewModel?
        var initialAddCardModel: AddCardViewModel?
        var initialAddSubscriptionModel: AddSubscriptionViewModel?
        var initialEditOneTimeModel: EditOneTimePaymentViewModel?
        var initialAssistantModel: AssistantViewModel?
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(AssistantView.launchArgument) {
            initialAssistantModel = model.makeAssistantModel()
        }
        if arguments.contains(AddInstallmentView.editLaunchArgument) {
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
        } else if arguments.contains(EditOneTimePaymentView.editLaunchArgument) {
            // Örnek veride tek seferlik ödeme başka ayda olabilir; depodaki ilki açılır.
            initialEditOneTimeModel = model.oneTimePaymentIDs().lazy
                .compactMap { model.makeEditOneTimeModel(id: $0) }
                .first
        } else if arguments.contains(AddCardView.editLaunchArgument) {
            initialAddCardModel = model.cardSubtotals.first.flatMap { model.makeEditCardModel(id: $0.id) }
        }
        #endif
        _addModel = State(initialValue: initialAddModel)
        _addCardModel = State(initialValue: initialAddCardModel)
        _addSubscriptionModel = State(initialValue: initialAddSubscriptionModel)
        _editOneTimeModel = State(initialValue: initialEditOneTimeModel)
        _assistantModel = State(initialValue: initialAssistantModel)
    }

    public var body: some View {
        scrollContent
            .toolbar {
                // Asistan düğmesi yalnızca iOS 26+ ve motor desteklenen bir sistemdeyken görünür.
                if Self.isAssistantOS, model.showsAssistant {
                    ToolbarItem(placement: .primaryAction) { assistantButton }
                }
            }
            // Başlık çubukta: sistem başlığı başlık (header) olarak okur ve AX5'te de kırpmaz.
            .navigationTitle(Text("Vadem", bundle: .module))
            .navigationDestination(isPresented: assistantPresented) {
                if let assistantModel {
                    AssistantView(model: assistantModel)
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            // Galeri gibi: çubuk ekranın renk şemasına ve arka planına sabitlenir.
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .toolbarBackground(Color(Color.vademBackground.resolve(in: environment)), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            // Form kapanınca (kaydedilse de iptal edilse de) veri yeniden yüklenir; değişiklik hemen görünür.
            .sheet(item: $addCardModel, onDismiss: reloadAfterForm) { addCardModel in
                AddCardView(model: addCardModel)
            }
            .sheet(item: $addModel, onDismiss: reloadAfterForm) { addModel in
                AddInstallmentView(model: addModel)
            }
            .sheet(item: $addSubscriptionModel, onDismiss: reloadAfterForm) { addSubscriptionModel in
                AddSubscriptionView(model: addSubscriptionModel)
            }
            .sheet(item: $editOneTimeModel, onDismiss: reloadAfterForm) { editOneTimeModel in
                EditOneTimePaymentView(model: editOneTimeModel)
            }
    }

    // Form kapanınca kabuk tüm sekmeleri yeniler; kabuk yoksa yalnızca Home.
    private func reloadAfterForm() {
        if let onDataChanged {
            onDataChanged()
        } else {
            model.reloadAfterChange()
        }
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
        .accessibilityLabel(Text("Assistant", bundle: .module))
        .accessibilityIdentifier("home.assistant")
    }

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    monthBar
                    // Hata durumunda da görünür (toplam sıfır): ekleme düğmesi her zaman erişilebilir.
                    hero(proxy)
                    sections
                }
                // 20 pt yan boşluk: ekranın sol kenarında her zaman arka plan rengi kalır.
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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

    // Ayın toplamı ve vadesi gelen kısmı; altında ekleme ve takvim düğmeleri.
    private func hero(_ proxy: ScrollViewProxy) -> some View {
        HeroPanel(
            title: String(localized: "Due this month", bundle: .module),
            total: model.total, paid: model.dueSoFar,
            captionPrefix: String(localized: "Due so far", bundle: .module), summaryIdentifier: "home.total"
        ) {
            if let onAdd {
                addButton(onAdd)
            }
            // Takvim gizliyken (hata durumu) kaydırılacak yer yok; düğme de gösterilmez.
            if !model.calendarDays.isEmpty {
                Button {
                    // Reduce Motion veya -ui-static-motion açıkken animasyonsuz kaydırır.
                    withAnimation(Motion.animation(Motion.quick, reduceMotion: reduceMotion)) {
                        proxy.scrollTo(Self.calendarAnchor, anchor: .top)
                    }
                } label: {
                    Label { Text("Calendar", bundle: .module) } icon: { Image(systemName: "calendar") }
                }
                .buttonStyle(.heroPill)
                // Etiket bölüm başlığıyla aynı ("Takvim"); ipucu düğmenin ne yaptığını söyler.
                .accessibilityHint(Text("Shows the month calendar", bundle: .module))
                .accessibilityIdentifier("home.showCalendar")
            }
        }
    }

    // "Add" ekleme sayfasını açar: taksit, abonelik ya da ödeme orada seçilir.
    private func addButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text("Add", bundle: .module) } icon: { Image(systemName: "plus") }
        }
        .buttonStyle(.heroPill)
        .accessibilityLabel(Text("Add payment", bundle: .module))
        .accessibilityIdentifier("home.add")
    }

    // Ay başlığı ve önceki/sonraki ay düğmeleri.
    private var monthBar: some View {
        HStack(spacing: 8) {
            monthButton(systemImage: "chevron.left", label: String(localized: "Previous month", bundle: .module), identifier: "home.previousMonth") {
                model.showPreviousMonth()
            }
            Text(model.monthTitle)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.vademTextPrimary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home.month")
            monthButton(systemImage: "chevron.right", label: String(localized: "Next month", bundle: .module), identifier: "home.nextMonth") {
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
            messageView(title: String(localized: "Something went wrong", bundle: .module), detail: message, systemImage: "exclamationmark.triangle")
                .accessibilityIdentifier("home.error")
        case .empty:
            if !model.hasCards { addCardPrompt }
            messageView(title: String(localized: "Nothing due this month", bundle: .module), detail: nil, systemImage: "checkmark.circle")
                .accessibilityIdentifier("home.empty")
        case .loaded:
            if !model.hasCards { addCardPrompt }
            // Gün seçiliyken o günün ödemeleri takvimin hemen altında, kart toplamlarından önce gelir.
            if model.selectedDay != nil {
                paymentsSection
                if !model.cardSubtotals.isEmpty { subtotalsSection }
            } else {
                if !model.cardSubtotals.isEmpty { subtotalsSection }
                paymentsSection
            }
        }
    }

    // Ödeme listesi ya da seçili günde ödeme yoksa boş gün mesajı.
    @ViewBuilder
    private var paymentsSection: some View {
        if model.rows.isEmpty, let dayText = model.selectedDayText {
            // Seçili günde ödeme yok; ayın geri kalanı dolu olduğundan "bu ay boş" denmez.
            messageView(
                title: String(localized: "Nothing due on \(dayText)", bundle: .module, comment: "The argument is a day, e.g. 12 October"),
                detail: nil, systemImage: "calendar")
                .accessibilityIdentifier("home.dayEmpty")
            showAllButton
        } else {
            listSection
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
            Text("Add a card to start tracking installments.", bundle: .module)
                .font(.body)
                .foregroundStyle(Color.vademTextPrimary)
            Button {
                addCardModel = model.makeAddCardModel()
            } label: {
                Label { Text("Add a card", bundle: .module) } icon: { Image(systemName: "plus.circle") }
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
            Text("Show all payments", bundle: .module)
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
            sectionTitle(String(localized: "By card", bundle: .module), identifier: "home.cards")
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
                    .accessibilityHint(Text("Edits the card", bundle: .module))
                    .accessibilityIdentifier("home.card.\(index)")
                }
            }
        }
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(listTitle, identifier: "home.list")
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
                    .accessibilityHint(Text("Edits the payment", bundle: .module))
                    .accessibilityIdentifier("home.row.\(index)")
                }
            }
        }
    }

    // "Payments" ya da seçili gün varsa "Payments on 12 October".
    private var listTitle: String {
        guard let dayText = model.selectedDayText else { return String(localized: "Payments", bundle: .module) }
        return String(localized: "Payments on \(dayText)", bundle: .module, comment: "The argument is a day, e.g. 12 October")
    }

    // Satırın kalemine göre taksit, abonelik ya da tek seferlik ödeme formu düzenleme modunda açılır.
    private func edit(_ row: HomeViewModel.Row) {
        switch row.entry.kind {
        case .installment:
            addModel = model.makeEditInstallmentModel(id: row.entry.itemID)
        case .subscription:
            addSubscriptionModel = model.makeEditSubscriptionModel(id: row.entry.itemID)
        case .oneTime:
            editOneTimeModel = model.makeEditOneTimeModel(id: row.entry.itemID)
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
            Text("Upcoming", bundle: .module)
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
            Text("Calendar", bundle: .module)
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
                Text(verbatim: "\(day)")
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
        // Bugün görselde yalnızca halkayla belirtilir; VoiceOver da "Bugün" duyar.
        .modifier(TodayAccessibilityValue(isToday: cell.isToday))
        .accessibilityAddTraits(cell.isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("home.calendar.day.\(day)")
    }
}

// Değer yalnızca bugüne eklenir; diğer günlerde boş bir değer okunmasın.
private struct TodayAccessibilityValue: ViewModifier {
    let isToday: Bool

    func body(content: Content) -> some View {
        if isToday {
            content.accessibilityValue(Text("Today", bundle: .module))
        } else {
            content
        }
    }
}

/// The "Vadem" title with the app version below it; shown only when the store is unavailable
/// (Home puts its title in the navigation bar).
@MainActor
struct AppHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Vadem", bundle: .module)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Color.vademTextPrimary)
                .accessibilityAddTraits(.isHeader)
            // Sürüm etiketi başlığın altında, daha küçük; ayrı erişilebilirlik etiketi yok.
            Text("Version \(VademCore.version)", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(Color.vademTextPrimary)
        }
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

    // "Everyday card · 3/12", "No card · One-time payment" veya "No card".
    private var detailText: String {
        [row.cardText, row.installmentText, oneTimeText].compactMap { $0 }.joined(separator: " · ")
    }

    // Tek seferlik ödeme alt satırda türüyle belirtilir; diğer türlerde nil.
    private var oneTimeText: String? {
        guard row.entry.kind == .oneTime else { return nil }
        return String(
            localized: "One-time payment", bundle: .module,
            comment: "Kind of a payment that is due once; shown and spoken in a payment row"
        )
    }
}

#if DEBUG
#Preview("Sample") {
    NavigationStack {
        HomeView(model: HomeSampleData.makeViewModel(), onAdd: {})
    }
}

#Preview("Empty") {
    NavigationStack {
        HomeView(model: HomeViewModel(
            repository: InMemoryPaymentRepository(), today: HomeSampleData.today, calendar: HomeSampleData.calendar
        ))
    }
}
#endif
