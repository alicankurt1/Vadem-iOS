import SwiftUI
import VademFeatures

// Uygulama giriş noktası; ekranlar VademFeatures modülünden gelir.
@main
struct VademApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // UI kontrolü `-ui-gallery` ile açınca kök ekran yerine tasarım galerisi gösterilir.
            if ProcessInfo.processInfo.arguments.contains("-ui-gallery") {
                DesignGalleryView()
            } else {
                RootView()
            }
            #else
            RootView()
            #endif
        }
    }
}
