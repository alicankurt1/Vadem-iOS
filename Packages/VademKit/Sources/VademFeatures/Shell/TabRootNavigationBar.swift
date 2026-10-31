import SwiftUI

// Sekme kök ekranlarının gezinme çubuğu: kaydırma kenarında saydam (ortam arka planı görünür),
// içerik altından geçerken sistem malzemesi (iOS 26'da cam + kaydırma kenarı efekti, iOS 18'de `.bar`).
// İtilen ekranlar ve sayfalar kendi düz zeminlerini ayrıca belirler; bu ayar onlara taşmaz.
@MainActor
struct TabRootNavigationBarModifier: ViewModifier {
    /// Çubuk arka planının görünürlüğü: `.automatic` sistemin kaydırma kenarı davranışını bırakır.
    nonisolated static var backgroundVisibility: Visibility { .automatic }

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            // Başlık ve düğmeler açıkta ve koyuda okunur kalsın: çubuk ekranın renk şemasını izler.
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .toolbarBackground(Self.backgroundVisibility, for: .navigationBar)
            #endif
    }
}

public extension View {
    /// Navigation bar style for a tab's root screen: transparent at the scroll edge so the
    /// ``AmbientBackground`` shows through, the system bar material (glass on iOS 26) once content
    /// scrolls under it. Pushed screens and sheets keep their own solid bar.
    func tabRootNavigationBar() -> some View {
        modifier(TabRootNavigationBarModifier())
    }
}
