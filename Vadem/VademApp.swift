import Foundation
import SwiftUI
import UIKit
import UserNotifications
import VademCore
import VademFeatures
import VademPersistence

#if DEBUG
// UI kontrolünün tasarım galerisini açan başlatma argümanı; kök ekran ve kurulum aynı değeri kullanır.
private let galleryLaunchArgument = "-ui-gallery"
#endif

// Bildirim merkezi temsilcisi açılış bitmeden kurulur: uygulamayı açan dokunuş kaçmaz.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let notificationTaps = NotificationTapHandler()

    func application(
        _ application: UIApplication,
        willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationTaps
        return true
    }
}

// Uygulama giriş noktası; ekranlar VademFeatures modülünden gelir.
@main
struct VademApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Kök ekran bir kez kurulur; depo her body çağrısında yeniden açılmaz.
    @State private var setup = AppSetup.make()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                // UI kontrolü `-ui-gallery` ile açınca kök ekran yerine tasarım galerisi gösterilir.
                if ProcessInfo.processInfo.arguments.contains(galleryLaunchArgument) {
                    DesignGalleryView()
                } else {
                    setup.root
                }
                #else
                setup.root
                #endif
            }
            // Açılış ekranı (Config/Vadem-Info.plist) ile aynı renk ve logo; kısa bir geçişle uygulamaya bırakır.
            .launchHandoff(background: Color("LaunchBackground"), logo: Image("LaunchLogo"))
            // Aylık özet bildirimine dokunulunca gelen kutusu açılır; soğuk açılışta bekleyen dokunuş burada teslim edilir.
            .onAppear {
                let model = setup.liveModel
                appDelegate.notificationTaps.onRoute = { route in
                    switch route {
                    case .inbox: model?.requestInbox()
                    }
                }
            }
            // Uygulama öne geldiğinde "bugün" yenilenir (gece yarısı / ay dönümü sonrası
            // çipler ve başlangıç ayı eskimesin). Örnek veride sabit bugün değişmez.
            // `initial: true`: soğuk açılışta da bir kez çalışır, hatırlatmalar açılışta da planlanır;
            // açılıştaki updateToday aynı günle yalnızca bir kez daha yükler, zararsızdır.
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    setup.liveModel?.updateToday(Date())
                    // Öne gelince hatırlatmalar ve widget da yenilenir (pencere kayar, izin Ayarlar'da değişmiş olabilir).
                    setup.refresh.sceneBecameActive()
                }
            }
        }
    }
}

/// The root screen and, when backed by the real store, the model whose "today" follows the clock.
@MainActor
private struct AppSetup {
    let root: RootView
    /// `nil` for sample data (fixed today) or when the store could not be opened.
    let liveModel: HomeViewModel?
    /// Refreshes the reminders and the widget; ``AppRefresh/none`` for sample data, the gallery
    /// or when the store could not be opened.
    let refresh: AppRefresh

    static func make() -> AppSetup {
        #if DEBUG
        // `-ui-sample-data`: sabit örnek veri ve sabit "bugün"; UI yakalaması her seferinde aynı.
        // Örnek veride hatırlatma kurulmaz ve widget yenilenmez: UI testlerinde sistem izin penceresi çıkmaz.
        // Gelen kutusu argümanları (`-ui-inbox` …) da örnek veriyle açar.
        if HomeSampleData.isRequested(in: ProcessInfo.processInfo.arguments) {
            return AppSetup(root: RootView(model: HomeSampleData.makeViewModel()), liveModel: nil, refresh: .none)
        }
        // Galeri gerçek depoya dokunmaz, hatırlatma kurmaz, widget'ı yenilemez.
        if ProcessInfo.processInfo.arguments.contains(galleryLaunchArgument) {
            return AppSetup(root: RootView.unavailable(), liveModel: nil, refresh: .none)
        }
        #endif
        do {
            let container = try VademPersistence.makeContainer(storage: .appGroup)
            let repository = SwiftDataPaymentRepository(container: container)
            // Gelen kutusu aynı depoda (V4 şeması); okundu durumu ve silinenler açılışlar arasında korunur.
            let inbox = SwiftDataInboxRepository(container: container)
            // Zamanlayıcı ve ayarlar sayfası aynı tercih deposunu ve aynı bildirim merkezini kullanır.
            let center = SystemReminderCenter()
            let preferences = UserDefaultsReminderPreferencesStore()
            let reminders = ReminderScheduler(
                repository: repository,
                center: center,
                preferences: preferences,
                calendar: .current
            )
            let refresh = AppRefresh(reminders: reminders, widgets: SystemWidgetReloader())
            let model = HomeViewModel(
                repository: repository,
                today: Date(),
                calendar: .current,
                // Form kapanıp Home yeniden yüklenince hatırlatmalar yeniden planlanır, widget yenilenir.
                onDataChanged: { refresh.dataChanged() },
                settings: SettingsDependencies(store: preferences, center: center, scheduler: reminders),
                inbox: inbox
            )
            return AppSetup(root: RootView(model: model), liveModel: model, refresh: refresh)
        } catch {
            // Depo açılamazsa çökmek yerine hata ekranı gösterilir.
            return AppSetup(root: RootView.unavailable(), liveModel: nil, refresh: .none)
        }
    }
}
