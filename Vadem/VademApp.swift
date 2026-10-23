import Foundation
import SwiftUI
import VademCore
import VademFeatures
import VademPersistence

#if DEBUG
// UI kontrolünün tasarım galerisini açan başlatma argümanı; kök ekran ve kurulum aynı değeri kullanır.
private let galleryLaunchArgument = "-ui-gallery"
#endif

// Uygulama giriş noktası; ekranlar VademFeatures modülünden gelir.
@main
struct VademApp: App {
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
            // Uygulama öne geldiğinde "bugün" yenilenir (gece yarısı / ay dönümü sonrası
            // çipler ve başlangıç ayı eskimesin). Örnek veride sabit bugün değişmez.
            // `initial: true`: soğuk açılışta da bir kez çalışır, hatırlatmalar açılışta da planlanır;
            // açılıştaki updateToday aynı günle yalnızca bir kez daha yükler, zararsızdır.
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    setup.liveModel?.updateToday(Date())
                    // Öne gelince hatırlatmalar da yenilenir (pencere kayar, izin Ayarlar'da değişmiş olabilir).
                    if let reminders = setup.reminders {
                        Task { await reminders.refresh() }
                    }
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
    /// Schedules the payment reminders; `nil` for sample data, the gallery or when the store could not be opened.
    let reminders: ReminderScheduler?

    static func make() -> AppSetup {
        #if DEBUG
        // `-ui-sample-data`: sabit örnek veri ve sabit "bugün"; UI yakalaması her seferinde aynı.
        // Örnek veride hatırlatma kurulmaz: UI testlerinde sistem izin penceresi çıkmaz.
        if ProcessInfo.processInfo.arguments.contains(HomeSampleData.launchArgument) {
            return AppSetup(root: RootView(model: HomeSampleData.makeViewModel()), liveModel: nil, reminders: nil)
        }
        // Galeri gerçek depoya dokunmaz ve hatırlatma kurmaz.
        if ProcessInfo.processInfo.arguments.contains(galleryLaunchArgument) {
            return AppSetup(root: RootView.unavailable(), liveModel: nil, reminders: nil)
        }
        #endif
        do {
            let container = try VademPersistence.makeContainer(storage: .appGroup)
            let repository = SwiftDataPaymentRepository(container: container)
            // Zamanlayıcı ve ayarlar sayfası aynı tercih deposunu ve aynı bildirim merkezini kullanır.
            let center = SystemReminderCenter()
            let preferences = UserDefaultsReminderPreferencesStore()
            let reminders = ReminderScheduler(
                repository: repository,
                center: center,
                preferences: preferences,
                calendar: .current
            )
            let model = HomeViewModel(
                repository: repository,
                today: Date(),
                calendar: .current,
                // Form kapanıp Home yeniden yüklenince hatırlatmalar da yeniden planlanır.
                onDataChanged: { Task { await reminders.refresh() } },
                settings: SettingsDependencies(store: preferences, center: center, scheduler: reminders)
            )
            return AppSetup(root: RootView(model: model), liveModel: model, reminders: reminders)
        } catch {
            // Depo açılamazsa çökmek yerine hata ekranı gösterilir.
            return AppSetup(root: RootView.unavailable(), liveModel: nil, reminders: nil)
        }
    }
}
