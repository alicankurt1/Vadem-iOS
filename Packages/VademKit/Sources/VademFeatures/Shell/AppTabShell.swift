import SwiftUI
import VademCore

/// The app's tab shell: This month (``HomeView``), ``AnalyticsView``, ``CardListView`` and
/// ``SettingsView``, switched with the ``FloatingTabBar`` floating over the content.
///
/// Every tab has its own `NavigationStack` and stays alive while hidden, so scroll positions and
/// pushed screens survive tab switches. Content scrolls under the bar; a bottom inset as tall as the
/// bar keeps the last row reachable. The ＋ button opens the ``AddFlowSheet`` from every tab; when a
/// form closes, Home, Analytics and Cards reload. The selected tab is published as
/// `EnvironmentValues.selectedAppTab`.
///
/// In debug builds ``AppTab/launchTab(in:)`` picks the first tab. ``AddInstallmentView/launchArgument``,
/// ``AddCardView/launchArgument`` and ``AddSubscriptionView/launchArgument`` open their add forms
/// (all errors shown with their `errorsLaunchArgument`); ``AddFlowSheet/launchArgument`` and
/// ``InstallmentFlowView/launchArgument`` open the Add sheet; ``SubscriptionFlowStep/launchArgument``,
/// ``OneTimeFlowStep/launchArgument`` and ``AddFlowGalleryStep/launchArgument`` open those flows at a
/// step (see ``HomeView/init(model:onAdd:onDataChanged:)`` for the edit forms and the assistant).
@MainActor
public struct AppTabShell: View {
    @State private var model: HomeViewModel
    @State private var analyticsModel: AnalyticsViewModel
    @State private var cardListModel: CardListViewModel
    @State private var settingsModel: SettingsViewModel
    @State private var selection: AppTab
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
        _isAddSheetPresented = State(initialValue: initialAddSheetPresented)
        _addModel = State(initialValue: initialAddModel)
        _addCardModel = State(initialValue: initialAddCardModel)
        _addSubscriptionModel = State(initialValue: initialAddSubscriptionModel)
    }

    public var body: some View {
        ZStack {
            tab(.home) {
                HomeView(model: model, onAdd: openAddSheet, onDataChanged: reloadAll)
            }
            tab(.analytics) {
                // Boş grafikteki "ödeme ekle" de ortak Ekle sayfasını açar.
                AnalyticsView(model: analyticsModel, onAddPayment: openAddSheet)
            }
            tab(.cards) {
                CardListView(model: cardListModel, onDataChanged: reloadAll)
            }
            tab(.settings) {
                SettingsView(model: settingsModel)
            }
        }
        // Çubuk içeriğin üstünde yüzer; klavye açılınca yerinde kalır (klavyenin altında).
        .overlay(alignment: .bottom) {
            FloatingTabBar(selection: $selection, onAdd: openAddSheet)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .environment(\.selectedAppTab, selection)
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

    // Her sekme kendi NavigationStack'inde ve hep canlı: gizliyken görünmez, dokunulamaz,
    // VoiceOver'dan gizli; kaydırma konumu ve itilmiş ekranlar korunur.
    private func tab(_ tab: AppTab, @ViewBuilder content: () -> some View) -> some View {
        let isSelected = selection == tab
        return NavigationStack {
            content()
        }
        // Çubuk kadar alt boşluk: son satır çubuğun üstüne kaydırılabilir, içerik altından geçer.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: barHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .opacity(isSelected ? 1 : 0)
        .allowsHitTesting(isSelected)
        .accessibilityHidden(!isSelected)
        .zIndex(isSelected ? 1 : 0)
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
