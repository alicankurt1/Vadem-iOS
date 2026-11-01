import SwiftUI
import VademCore
#if os(iOS)
import UIKit
#endif

/// The app's tab shell: This month (``HomeView``), ``AnalyticsView``, ``CardListView`` and
/// ``SettingsView``, switched with the ``FloatingTabBar`` floating over the content.
///
/// Every tab has its own `NavigationStack` in a `TabView` whose system tab bar is hidden: tabs stay
/// alive while not shown (scroll positions and pushed screens survive tab switches), and only the
/// selected tab is in the view and accessibility hierarchy. Content scrolls under the bar; at the end
/// of a screen the last row stops ``barGap`` points above the bar (and its ＋ button). The space is
/// reserved as extra bottom safe area on each tab's navigation controller, so it applies to the root
/// and every pushed screen, `ScrollView`s and `List`s/`Form`s alike, on top of the home indicator
/// (counted once); sheets are not affected. The ＋ button opens the ``AddFlowSheet`` from every tab; when a
/// form closes, Home, Analytics and Cards reload. The selected tab is published as
/// `EnvironmentValues.selectedAppTab`. Each tab's root screen sits on an ``AmbientBackground`` tinted
/// with the selected tab's ``AppTab/ambientTint``. The new tab is shown at once (no blank frame) and settles in with
/// one calm cross-fade: a slight fade and a very slight blur, no movement (``Motion/tabSwitchStart(from:to:)``);
/// the tint cross-fades in sync (``Motion/ambientTint``). Fast taps restart it and end on the last tab. The staggered
/// entry plays only on the tab shown at launch (``Motion/entryPlays(tab:launchTab:)``); other tabs appear settled.
/// The ``FloatingTabBar`` is not part of the effect. Under Reduce Motion and `-ui-static-motion` the switch is instant.
///
/// In debug builds ``AppTab/launchTab(in:)`` picks the first tab. ``AddInstallmentView/launchArgument``,
/// ``AddCardView/launchArgument`` and ``AddSubscriptionView/launchArgument`` open their add forms
/// (all errors shown with their `errorsLaunchArgument`); ``AddFlowSheet/launchArgument`` and
/// ``InstallmentFlowView/launchArgument`` open the Add sheet (``StatementImportLaunchState/launchArgument`` opens it
/// on the statement import screen, ``StatementReviewView/launchArgument`` on the review step); ``SubscriptionFlowStep/launchArgument``,
/// ``OneTimeFlowStep/launchArgument`` and ``AddFlowGalleryStep/launchArgument`` open those flows at a
/// step (see ``HomeView/init(model:onAdd:onDataChanged:)`` for the edit forms, the assistant and the inbox).
/// ``HomeViewModel/requestInbox()`` selects This month, where Home pushes the ``InboxView``.
/// On first launch (``OnboardingDecision``) the ``OnboardingView`` covers the shell as a layer in
/// the same hierarchy (not a full-screen cover); Skip or Get started fades it out. The decision reads
/// the repository synchronously in `init` (so Home never flashes) and is taken once per process:
/// a re-created shell neither reads the store again nor reopens or re-marks the walkthrough.
@MainActor
public struct AppTabShell: View {
    @State private var model: HomeViewModel
    @State private var analyticsModel: AnalyticsViewModel
    @State private var cardListModel: CardListViewModel
    @State private var settingsModel: SettingsViewModel
    @State private var selection: AppTab
    // TabView'de gösterilen sekme; `selection` değişince animasyonsuz ve hemen eşitlenir (boş kare olmaz).
    @State private var displayedTab: AppTab
    // Yeni sekmenin yerine oturmaya başladığı görünüm (saydamlık ve hafif bulanıklık).
    @State private var tabSwitchStart = Motion.TabSwitchState.settled
    // Her animasyonlu geçişte artar ve oturma animasyonunu baştan başlatır.
    @State private var tabSwitchCount = 0
    // Açılışta gösterilen sekme; kademeli giriş yalnızca bu sekmede oynar.
    private let launchTab: AppTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Ortam arka planının rengi; seçimle birlikte değişir, geçişi AmbientBackground kendisi yumuşatır.
    @State private var ambientTab: AppTab
    // Yüzen çubuğun ölçülen yüksekliği (alt dolgusu ve ＋ düğmesi dahil); sekme içeriği bu kadar
    // ve `barGap` kadar alttan boşluk bırakır.
    @State private var barHeight: CGFloat = 0

    /// Extra space between the end of a tab's content and the top of the ``FloatingTabBar``, in points.
    public static let barGap: CGFloat = 12

    // İlk açılış tanıtımı; nil iken kapalı. Kabuğun içinde katman olarak çizilir (tam ekran örtü değil),
    // böylece açılış logosu geçişi üstte kalır ve her zamanki gibi solar.
    @State private var onboardingModel: OnboardingViewModel?

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
        let settings = model.makeSettingsModel()
        _settingsModel = State(initialValue: settings)
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
                    || arguments.contains(InstallmentFlowView.launchArgument)
                    || StatementImportLaunchState.state(in: arguments) != nil
                    || arguments.contains(StatementReviewView.launchArgument) {
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
        launchTab = initialTab
        // Karar ilk karede verilir (veri depodan eşzamanlı okunur): Home bir an görünüp kaybolmaz.
        // Süreç başına bir kez: kabuk yeniden kurulursa depo tekrar okunmaz, görüldü tekrar yazılmaz.
        var initialOnboardingModel: OnboardingViewModel?
        switch Self.takeLaunchOnboardingDecision(for: model) {
        case .show:
            // Ayarlar sekmesiyle aynı model: seçim Ayarlar'daki hatırlatma anahtarında görünür.
            initialOnboardingModel = settings.makeOnboardingModel()
        case .hideAndMarkSeen:
            OnboardingViewModel.markSeen()
        case .hide:
            break
        }
        _selection = State(initialValue: initialTab)
        _displayedTab = State(initialValue: initialTab)
        _ambientTab = State(initialValue: initialTab)
        _isAddSheetPresented = State(initialValue: initialAddSheetPresented)
        _addModel = State(initialValue: initialAddModel)
        _addCardModel = State(initialValue: initialAddCardModel)
        _addSubscriptionModel = State(initialValue: initialAddSubscriptionModel)
        _onboardingModel = State(initialValue: initialOnboardingModel)
    }

    // Açılış kararı alındı mı; ana aktörde, süreç boyunca bir kez true olur.
    // Bayrak süreç genelidir: aynı süreçte kurulan ikinci bir kabuk (ör. yeniden kurulum) `.hide` alır.
    private static var hasTakenLaunchOnboardingDecision = false

    // Açılış kararı yalnızca ilk çağrıda hesaplanır (yan etkiler dahil); sonraki çağrılar `.hide` döner.
    private static func takeLaunchOnboardingDecision(for model: HomeViewModel) -> OnboardingDecision {
        guard !hasTakenLaunchOnboardingDecision else { return .hide }
        hasTakenLaunchOnboardingDecision = true
        return onboardingDecision(for: model)
    }

    // Görüldü sürümü, veri olup olmadığı ve başlatma argümanları; depo okunamazsa tanıtım açılmaz.
    private static func onboardingDecision(for model: HomeViewModel) -> OnboardingDecision {
        let arguments = ProcessInfo.processInfo.arguments
        let seenVersion = OnboardingViewModel.seenVersion()
        guard let hasData = try? model.hasAnyData() else {
            // Okuma hatasında yalnızca açık istek (UI testi) tanıtımı açar; görüldü kaydedilmez.
            let decision = OnboardingDecision.decide(seenVersion: seenVersion, hasData: true, launchArguments: arguments)
            return decision == .show ? .show : .hide
        }
        return OnboardingDecision.decide(seenVersion: seenVersion, hasData: hasData, launchArguments: arguments)
    }

    public var body: some View {
        shell
            // Tanıtım açıkken altındaki kabuk VoiceOver'da ve dokunuşta yok sayılır.
            .accessibilityHidden(onboardingModel != nil)
            .overlay {
                if let onboardingModel {
                    OnboardingView(model: onboardingModel)
                        .transition(.opacity)
                        .onChange(of: onboardingModel.isFinished) { _, isFinished in
                            if isFinished { closeOnboarding() }
                        }
                }
            }
    }

    // Tanıtım kapanır; hareket açıksa kısa bir solma ile (Reduce Motion ve -ui-static-motion'da anlık).
    private func closeOnboarding() {
        withAnimation(Motion.animation(Motion.quick, reduceMotion: reduceMotion)) {
            onboardingModel = nil
        }
    }

    private var shell: some View {
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
        // Sekme geçişi: yeni içerik hemen gösterilir, kaymadan hafif bir saydamlık ve bulanıklıkla belirir.
        .tabSwitchEffect(from: tabSwitchStart, trigger: tabSwitchCount)
        // Saydamlık ve bulanıklık sırasında kenarda pencere rengi değil düz zemin görünür.
        .background { Color.vademBackground.ignoresSafeArea() }
        .onChange(of: selection) { oldTab, newTab in switchTab(from: oldTab, to: newTab) }
        // Bildirimden gelen kutusu istendi: This month seçilir, Home gelen kutusunu iter.
        .onChange(of: model.inboxRequestCount) { _, _ in selection = .home }
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
                makeOneTimeFlow: { model.makeOneTimeFlowModel() },
                // Ekstre cihazda okunur; bulunan taksitler yalnızca inceleme ekranında onaylanınca kaydedilir.
                makeStatementImport: { StatementImportViewModel(source: OnDeviceStatementTextSource()) },
                makeStatementReview: { model.makeStatementReviewModel(candidates: $0) }
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
                // Çubuk payı yığının UINavigationController'ına alt güvenli alan olarak eklenir.
                // NavigationStack'in dışına konan safeAreaInset TabView sayfasında kaydırma içeriğine
                // ulaşmıyordu (son satırlar çubuğun altında kalıyordu). UIKit güvenli alanı ise kök ve
                // itilen tüm ekranlara (ScrollView, List, Form) iner; sayfalar (sheet) etkilenmez.
                // Çubuk ana ekran çizgisinin üstünde durur, pay da o güvenli alana eklenir: çizgi bir kez
                // sayılır. İçerik kaydırılırken yine çubuğun altından geçer; yalnızca bitiş konumu değişir.
                .background {
                    NavigationBottomInset(bottom: barHeight + Self.barGap)
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                #endif
        }
        #if os(iOS)
        // Sistem sekme çubuğu hiç görünmez; itilen ekranlarda da.
        .toolbar(.hidden, for: .tabBar)
        #endif
        // Kademeli giriş yalnızca açılıştaki sekmede; diğerleri ilk görünüşlerinde hemen yerinde görünür.
        .environment(\.motionEntryEnabled, Motion.entryPlays(tab: tab, launchTab: launchTab))
        .tag(tab)
    }

    // Yeni sekme aynı güncellemede gösterilir; eski ve yeni arasında boş kare yoktur. Hareket açıksa yeni
    // sekme hafif saydam ve bulanık başlangıç görünümünden yerine oturur (yön yok, kayma yok). Art arda dokunuşlarda (A→B→C) her geçiş
    // animasyonu baştan başlatır; sonuç hep son seçilen sekmedir, bekleyen tamamlanma işi yoktur.
    // Hareket kapalıyken (Reduce Motion, -ui-static-motion) sayaç artmaz: geçiş anlıktır.
    private func switchTab(from oldTab: AppTab, to newTab: AppTab) {
        let animated = Motion.isAnimated(reduceMotion: reduceMotion, staticMotionRequested: Motion.staticMotionRequested)
        // Çubuğun hap animasyonu bu işleme taşınmasın: sekme içeriği animasyonsuz değişir.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            displayedTab = newTab
            if animated {
                tabSwitchStart = Motion.tabSwitchStart(from: oldTab, to: newTab)
                tabSwitchCount += 1
            }
        }
        // Renk geçişini AmbientBackground kendisi yapar; süre ve eğri içerikle aynı (Reduce Motion'da yok).
        ambientTab = newTab
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

#if os(iOS)
/// Adds `bottom` points of extra bottom safe area to the `UINavigationController` it is placed in,
/// so the root screen and every pushed screen end their content above the floating tab bar.
@MainActor
private struct NavigationBottomInset: UIViewControllerRepresentable {
    let bottom: CGFloat

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.bottom = bottom
    }

    // Görünmez yardımcı denetleyici; yalnızca bağlı olduğu gezinme denetleyicisinin güvenli alanını ayarlar.
    final class Controller: UIViewController {
        var bottom: CGFloat = 0 {
            didSet { apply() }
        }

        override func loadView() {
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            self.view = view
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        // Değer değişmediyse dokunulmaz: gereksiz yerleşim turu olmaz.
        private func apply() {
            guard let navigationController, navigationController.additionalSafeAreaInsets.bottom != bottom else { return }
            navigationController.additionalSafeAreaInsets.bottom = bottom
        }
    }
}
#endif

#if DEBUG
#Preview {
    AppTabShell(model: HomeSampleData.makeViewModel())
}
#endif
