import SwiftUI
import VademFeatures

// Uygulama giriş noktası; ekranlar VademFeatures modülünden gelir.
@main
struct VademApp: App {
    // UI kontrolü `-ui-gallery` ile açınca kök ekran yerine tasarım galerisi gösterilir.
    private let showsDesignGallery = ProcessInfo.processInfo.arguments.contains("-ui-gallery")

    var body: some Scene {
        WindowGroup {
            if showsDesignGallery {
                DesignGalleryView()
            } else {
                RootView()
            }
        }
    }
}
