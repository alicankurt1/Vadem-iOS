import SwiftUI
import VademCore

/// The app's tab shell: This month (``HomeView``), ``AnalyticsView``, ``CardListView`` and
/// ``SettingsView``, switched with the ``FloatingTabBar`` floating over the content.
///
/// Every tab has its own `NavigationStack` in a `TabView` whose system tab bar is hidden: tabs stay
/// alive while not shown (scroll positions and pushed screens survive tab switches), and only the
/// selected tab is in the view and accessibility hierarchy. Content scrolls under the bar; a bottom
/// inset as tall as the bar keeps the last row reachable. The ＋ button opens the ``AddFlowSheet`` from every tab; when a
/// form closes, Home, Analytics and Cards reload. The selected tab is published as
/// `EnvironmentValues.selectedAppTab`. Each tab's root screen sits on an ``AmbientBackground`` tinted
/// with the selected tab's ``AppTab/ambientTint``; switching tabs cross-fades the tint and plays the shared ``Motion`` tab
/// transition (off under Reduce Motion and `-ui-static-motion`).
///
/// In debug builds ``AppTab/launchTab(in:)`` picks the first tab. ``AddInstallmentView/launchArgument``,
/// ``AddCardView/launchArgument`` and ``AddSubscriptionView/launchArgument`` open their add forms
/// (all errors shown with their `errorsLaunchArgument`); ``AddFlowSheet/launchArgument`` and
/// ``InstallmentFlowView/launchArgument`` open the Add sheet; ``SubscriptionFlowStep/launchArgument``,
/// ``OneTimeFlowStep/launchArgument`` and ``AddFlowGalleryStep/launchArgument`` open those flows at a
/// step (see ``HomeView/init(model:onAdd:onDataChanged:)`` for the edit forms, the assistant and the inbox).
/// ``HomeViewModel/requestInbox()`` selects This month, where Home pushes the ``InboxView``.
@MainActor
public struct AppTabShell: View {
    @State private var model: HomeViewModel
    @State private var analyticsModel: AnalyticsViewModel
    @State private var cardListModel: CardListViewModel
    @State private var settingsModel: SettingsViewModel
    @State private var selection: AppTab
    // TabView'de gösterilen sekme; geçiş animasyonunda eski sekme sönünce `selection`a eşitlenir.
    @State private var displayedTab: AppTab
    // Sekme geçişinin anlık görünümü (sönme, bulanıklık, ölçek).
    @State private var tabPhase: Motion.TabSwitchPhase = .visible
    // Her yeni sekme geçişinde artar; yalnızca en son geçişin tamamlanma işi ve Task'ı uygulanır.
    @State private var tabSwitchGeneration = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Ortam arka planının rengi; seçimden bir adım sonra değişir, yeni sekme eski renkten geçişle açılır.
    @State private var ambientTab: AppTab
    // Yüzen çubuğun ölçülen yüksekliği; sekme içeriği bu kadar alttan boşluk bırakır.
    @State private var barHeight: CGFloat = 0
    // "Ekle" sayfası açık mı.
    @State private var isAddSheetPresented: Bool
    // Ekle sayfasında seçilen tür; sayfa kapanınca o türün formu açılır.
    @State private var pendingAddKind: AddFlowKind?
    // Ekle sayfasından ya da başlatma argümanından açılan formlar; nil iken sayfa kapalı.
    @State private var addModel: AddInstallmentViewModel?
    @State private var addCardModel: AddCardViewModel?
    @State private var addSubscriptionModel: AddSubscriptionViewModel?
    #if DEBUG
    // UI kontrolü için açılan ortak adım galerisinin başlangıç adımı; nil iken kapalı.
    @State private var addFlowGalleryStep: AddFlowGalleryStep?
    // UI kontrolü için doğrudan bir adımında açılan abonelik akışı; nil iken kapalı.
    @State private var subscriptionFlowModel: SubscriptionFlowViewModel?
    // UI kontrolü için doğrudan bir adımında açılan tek seferlik ödeme akışı; nil iken kapalı.
    @State private var oneTimeFlowModel: OneTimeFlowViewModel?
    #endif

    /// Creates the shell for `model`, showing This month (or, in debug builds, the tab a launch argument selects).
    public init(model: HomeViewModel) {
        _model = State(initialValue: model)
        _analyticsModel = State(initialValue: model.makeAnalyticsModel())
        _cardListModel = State(initialValue: model.makeCardListModel())
        _settingsModel = State(initialValue: model.makeSettingsModel())
        var initialTab = AppTab.home
        var initialAddSheetPresented = false
        var initialAddModel: AddInstallmentViewModel?
        var initialAddCardModel: AddCardViewModel?
        var initialAddSubscriptionModel: AddSubscriptionViewModel?
        #if DEBUG
        var initialAddFlowGalleryStep: AddFlowGalleryStep?
        var initialSubscriptionFlowModel: SubscriptionFlowViewModel?
        var initialOneTimeFlowModel: OneTimeFlowViewModel?
        let arguments = ProcessInfo.processInfo.arguments
        initialTab = AppTab.launchTab(in: arguments) ?? .home
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
        } else if arguments.contains(AddFlowSheet.launchArgument)
                    || arguments.contains(InstallmentFlowView.launchArgument) {
            initialAddSheetPresented = true
        } else if let step = SubscriptionFlowStep.step(in: arguments) {
            // Kart adımında bir seçim görünsün diye ilk kart son kullanılan sayılır.
            model.lastUsedCardID = model.pickerCards().first?.id
            // Tutar adımından sonraki adımlar örnek bir tutarla açılır (Decimal, Double değil).
            initialSubscriptionFlowModel = model.makeSubscriptionFlowModel(
                start: step, amount: step == .amount ? nil : Decimal(14990) / 100
            )
        } else if let step = OneTimeFlowStep.step(in: arguments) {
            // Kart adımında bir seçim görünsün diye ilk kart son kullanılan sayılır; tutar Decimal.
            initialOneTimeFlowModel = model.makeOneTimeFlowModel(
                start: step, amount: step == .amount ? nil : Decimal(1_500),
                lastUsedCardID: model.pickerCards().first?.id
            )
        } else {
            initialAddFlowGalleryStep = AddFlowGalleryStep.step(in: arguments)
        }
        _addFlowGalleryStep = State(initialValue: initialAddFlowGalleryStep)
        _subscriptionFlowModel = State(initialValue: initialSubscriptionFlowModel)
        _oneTimeFlowModel = State(initialValue: initialOneTimeFlowModel)
        #endif
        _selection = State(initialValue: initialTab)
        _displayedTab = State(initialValue: initialTab)
        _ambientTab = State(initialValue: initialTab)
        _isAddSheetPresented = State(initialValue: initialAddSheetPresented)
        _addModel = State(initialValue: initialAddModel)
        _addCardModel = State(initialValue: initialAddCardModel)
        _addSubscriptionModel = State(initialValue: initialAddSubscriptionModel)
    }

    public var body: some View {
        // Sistem TabView'i sekmeleri canlı tutar ve yalnızca seçili sekmeyi hiyerarşide (VoiceOver ve
        // UI testleri dahil) gösterir; sistem çubuğu gizli, yerine yüzen çubuk çizilir.
        TabView(selection: $displayedTab) {
            tab(.home) {
                HomeView(model: model, onAdd: openAddSheet, onDataChanged: reloadAll)
            }
            tab(.analytics) {
                // Boş grafikteki "ödeme ekle" de ortak Ekle sayfasını açar. Kart yokken de çalışır:
                // akışların kart adımında "Kart yok" ve "Yeni kart" satırları hep vardır.
                AnalyticsView(model: analyticsModel, onAddPayment: openAddSheet)
            }
            tab(.cards) {
                CardListView(model: cardListModel, onDataChanged: reloadAll)
            }
            tab(.settings) {
                SettingsView(model: settingsModel)
            }
        }
        // Sekme geçişi: eski içerik bulanıklaşıp küçülerek söner, yenisi belirir (Motion'dan).
        .tabSwitchEffect(tabPhase)
        .onChange(of: selection) { _, newTab in switchTab(to: newTab) }
        // Bildirimden gelen kutusu istendi: This month seçilir, Home gelen kutusunu iter.
        .onChange(of: model.inboxRequestCount) { _, _ in selection = .home }
        // Çubuk içeriğin üstünde yüzer; klavye açılınca yerinde kalır (klavyenin altında).
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: $selection, onAdd: openAddSheet)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .environment(\.selectedAppTab, selection)
        // Geçiş animasyonunu AmbientBackground kendisi seçer (Reduce Motion'da yok).
        .onChange(of: selection) { _, tab in ambientTab = tab }
        // Form kapanınca (kaydedilse de iptal edilse de) tüm sekmeler yeniden yüklenir.
        .sheet(item: $addModel, onDismiss: reloadAll) { addModel in
            AddInstallmentView(model: addModel)
        }
        .sheet(item: $addCardModel, onDismiss: reloadAll) { addCardModel in
            AddCardView(model: addCardModel)
        }
        .sheet(item: $addSubscriptionModel, onDismiss: reloadAll) { addSubscriptionModel in
            AddSubscriptionView(model: addSubscriptionModel)
        }
        // Ekle sayfası: seçilen formu sayfa tamamen kapandıktan sonra açar (iki sayfa üst üste açılamaz).
        // Sayfa içindeki akış kaydetmiş olabilir; sayfa kapanınca sekmeler yeniden yüklenir.
        .sheet(isPresented: $isAddSheetPresented, onDismiss: addSheetDismissed) {
            AddFlowSheet(
                makeInstallmentFlow: { model.makeInstallmentFlowModel() },
                makeSubscriptionFlow: { model.makeSubscriptionFlowModel() },
                makeAddCardModel: model.makeAddCardModel,
                makeOneTimeFlow: { model.makeOneTimeFlowModel() }
            ) { kind in
                pendingAddKind = kind
                isAddSheetPresented = false
            }
        }
        #if DEBUG
        // Yeni kart eklenmiş olabilir; galeri kapanınca sekmeler yeniden yüklenir.
        .sheet(item: $addFlowGalleryStep, onDismiss: reloadAll) { step in
            AddFlowGalleryView(
                start: step, cards: model.pickerCards(), lastUsedCardID: model.pickerCards().first?.id,
                makeAddCardModel: model.makeAddCardModel
            )
        }
        .sheet(item: $subscriptionFlowModel, onDismiss: reloadAll) { flowModel in
            SubscriptionFlowView(model: flowModel, makeAddCardModel: model.makeAddCardModel)
        }
        .sheet(item: $oneTimeFlowModel, onDismiss: reloadAll) { flowModel in
            OneTimeFlowView(model: flowModel)
        }
        #endif
    }

    // Her sekme kendi NavigationStack'inde; TabView sekmeyi seçili değilken de canlı tutar,
    // kaydırma konumu ve itilmiş ekranlar korunur.
    private func tab(_ tab: AppTab, @ViewBuilder content: () -> some View) -> some View {
        NavigationStack {
            content()
                // Sadece kök ekranın arkasında; itilen ekranlar kendi düz zeminleriyle üstünü örter.
                .background { AmbientBackground(tint: ambientTab.ambientTint) }
                #if os(iOS)
                // Kök ekranda da gizlenir: yığın içi tercih sistem çubuğunu geri getirmesin.
                .toolbar(.hidden, for: .tabBar)
                #endif
        }
        // Çubuğun yüksekliği kadar alt boşluk. Çubuk alt güvenli alanın (ana ekran çizgisi) üstünde
        // durur ve bu boşluk da güvenli alana eklenir; çizgi payı iki kez sayılmaz, son satır çubuğun
        // tam üstünde biter, içerik çubuğun altından geçer.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: barHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        #if os(iOS)
        // Sistem sekme çubuğu hiç görünmez; itilen ekranlarda da.
        .toolbar(.hidden, for: .tabBar)
        #endif
        .tag(tab)
    }

    // Hareket kapalıyken (Reduce Motion, -ui-static-motion) sekme anında değişir. Açıkken önce eski
    // sekme söner, sonra yeni sekme yerine geçip belirir. Art arda dokunuşlarda (A→B→C) son seçim kazanır:
    // - Sönme sürerken (.leaving) yeni geçiş başlatılmaz; süren sönme bitince zaten en son `selection`
    //   gösterilir. Aynı değere ikinci bir withAnimation tamamlanmayı hemen tetikler, bu yüzden atlanır.
    // - Her yeni geçiş sayacı artırır; eski geçişlerin tamamlanma işi ve belirme Task'ı sayaç tutmazsa
    //   hiçbir şey yapmaz. Böylece değiştirme ve .entering yalnızca bir kez uygulanır (titreme olmaz).
    // - Belirme sırasında (.entering veya .visible'a giderken) dokunulursa yeni sönme oradan başlar.
    private func switchTab(to newTab: AppTab) {
        guard Motion.isAnimated(reduceMotion: reduceMotion, staticMotionRequested: Motion.staticMotionRequested) else {
            // Süren animasyonlu geçiş varsa geçersiz kılınır.
            tabSwitchGeneration += 1
            displayedTab = newTab
            tabPhase = .visible
            return
        }
        guard tabPhase != .leaving else { return }
        tabSwitchGeneration += 1
        let generation = tabSwitchGeneration
        withAnimation(Motion.tabOut) {
            tabPhase = .leaving
        } completion: {
            guard generation == tabSwitchGeneration else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                displayedTab = selection
                tabPhase = .entering
            }
            // Bir sonraki turda: yeni sekme önce görünmez çizilir, sonra yalnızca saydamlıkla belirir.
            // Bu arada yeni bir geçiş başladıysa sayaç değişmiştir; dokunulmaz.
            Task { @MainActor in
                guard generation == tabSwitchGeneration else { return }
                withAnimation(Motion.tabIn) { tabPhase = .visible }
            }
        }
    }

    private func openAddSheet() {
        isAddSheetPresented = true
    }

    // Ekle sayfası kapanınca sekmeler yenilenir, sonra (seçildiyse) türün mevcut formu açılır.
    private func addSheetDismissed() {
        reloadAll()
        defer { pendingAddKind = nil }
        switch pendingAddKind {
        case .subscription:
            addSubscriptionModel = model.makeAddSubscriptionModel()
        case .installment, .payment, nil:
            // Taksit ve ödeme akışları sayfanın içinde kaydeder; yenileme yukarıda yapıldı.
            break
        }
    }

    // Veri değişmiş olabilir: Home (hatırlatmalar ve widget dahil), Analytics ve Kartlar yeniden yüklenir.
    private func reloadAll() {
        model.reloadAfterChange()
        analyticsModel.reload()
        cardListModel.refresh()
    }
}

#if DEBUG
#Preview {
    AppTabShell(model: HomeSampleData.makeViewModel())
}
#endif
