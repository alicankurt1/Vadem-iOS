import Foundation
import SwiftUI
import VademCore
import VademFeatures
import VademPersistence

// Uygulama giriş noktası; ekranlar VademFeatures modülünden gelir.
@main
struct VademApp: App {
    // Kök ekran bir kez kurulur; depo her body çağrısında yeniden açılmaz.
    @State private var root = VademApp.makeRoot()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // UI kontrolü `-ui-gallery` ile açınca kök ekran yerine tasarım galerisi gösterilir.
            if ProcessInfo.processInfo.arguments.contains("-ui-gallery") {
                DesignGalleryView()
            } else {
                root
            }
            #else
            root
            #endif
        }
    }

    @MainActor
    private static func makeRoot() -> RootView {
        #if DEBUG
        // `-ui-sample-data`: sabit örnek veri ve sabit "bugün"; UI yakalaması her seferinde aynı.
        if ProcessInfo.processInfo.arguments.contains(HomeSampleData.launchArgument) {
            return RootView(model: HomeSampleData.makeViewModel())
        }
        #endif
        do {
            let container = try VademPersistence.makeContainer(storage: .appGroup)
            let model = HomeViewModel(
                repository: SwiftDataPaymentRepository(container: container),
                today: Date(),
                calendar: .current
            )
            return RootView(model: model)
        } catch {
            // Depo açılamazsa çökmek yerine hata ekranı gösterilir.
            return RootView.unavailable()
        }
    }
}
