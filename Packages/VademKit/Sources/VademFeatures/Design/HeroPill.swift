import SwiftUI

/// A capsule button style for hero actions ("Add", "Calendar"): `vademAccent` fill
/// with a `vademOnAccent` label.
public struct HeroPill: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .heroPillLabel()
            // Basılı durum yalnızca saydamlıkla gösterilir; sürekli animasyon yok.
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension View {
    // Hap görünümü; düğme stili uygulanamayan yerlerde (örn. Menu etiketi) de aynısı kullanılır.
    @MainActor
    func heroPillLabel() -> some View {
        font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.vademOnAccent)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            // En az 44 pt dokunma alanı.
            .frame(minHeight: 44)
            .background(Color.vademAccent, in: .capsule)
            .contentShape(.capsule)
    }
}

public extension ButtonStyle where Self == HeroPill {
    /// The ``HeroPill`` capsule style.
    static var heroPill: HeroPill { HeroPill() }
}

#Preview {
    HStack {
        Button {} label: { Label("Add", systemImage: "plus") }
        Button {} label: { Label("Calendar", systemImage: "calendar") }
    }
    .buttonStyle(.heroPill)
    .padding()
    .background(Color.vademHero)
}
