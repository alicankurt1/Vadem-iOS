import SwiftUI
import VademCore

// Uygulamanın kök ekranı; özellik ekranları ileriki fazlarda buraya bağlanacak.
@MainActor
public struct RootView: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView(
            "Vadem",
            systemImage: "creditcard",
            description: versionLabel
        )
    }

    // Sürüm etiketi: varsayılan .secondary stil açık temada kontrast denetimini
    // geçemiyor; .primary ile okunabilir kalırken hiyerarşiyi küçük font sağlıyor.
    // Görünen metin doğrudan okunabilir; ayrı erişilebilirlik etiketi yok, böylece
    // VoiceOver ile ekrandaki metin aynı (denetim uyumsuzluğu "kırpılmış" sayıyor).
    private var versionLabel: Text {
        Text("Version \(VademCore.version)")
            .font(.subheadline)
            .foregroundStyle(.primary)
    }
}

#Preview {
    RootView()
}
