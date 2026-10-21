import Foundation
import SwiftUI
import VademCore
import VademFeatures
import VademPersistence

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
                if ProcessInfo.processInfo.arguments.contains("-ui-gallery") {
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
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    setup.liveModel?.updateToday(Date())
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

    static func make() -> AppSetup {
        #if DEBUG
        // `-ui-sample-data`: sabit örnek veri ve sabit "bugün"; UI yakalaması her seferinde aynı.
        if ProcessInfo.processInfo.arguments.contains(HomeSampleData.launchArgument) {
            return AppSetup(root: RootView(model: HomeSampleData.makeViewModel()), liveModel: nil)
        }
        #endif
        do {
            let container = try VademPersistence.makeContainer(storage: .appGroup)
            let model = HomeViewModel(
                repository: SwiftDataPaymentRepository(container: container),
                today: Date(),
                calendar: .current
            )
            return AppSetup(root: RootView(model: model), liveModel: model)
        } catch {
            // Depo açılamazsa çökmek yerine hata ekranı gösterilir.
            return AppSetup(root: RootView.unavailable(), liveModel: nil)
        }
    }
}
