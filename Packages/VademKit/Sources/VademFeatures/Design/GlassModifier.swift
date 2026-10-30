import SwiftUI

// Sadece yüzen kontroller için: iOS 26+'da Liquid Glass, daha eskide materyal.
@MainActor
struct GlassModifier<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

public extension View {
    /// Glass background for floating controls only, in a capsule.
    /// For cards, hero pills and the ＋ button use ``vademGlassSurface(in:tint:)`` instead.
    /// Uses `glassEffect` on iOS 26+ and a material on iOS 18–25.
    func vademGlass() -> some View {
        modifier(GlassModifier(shape: Capsule()))
    }

    /// Glass background for floating controls only, in `shape`.
    /// For cards, hero pills and the ＋ button use ``vademGlassSurface(in:tint:)`` instead.
    /// Uses `glassEffect` on iOS 26+ and a material on iOS 18–25.
    func vademGlass<S: Shape>(in shape: S) -> some View {
        modifier(GlassModifier(shape: shape))
    }
}

// Kartlar, hero hapları ve ＋ düğmesi için cam yüzey: yarı saydam materyal, ince açık kenar,
// yumuşak gölge. Tüm sürümlerde aynı çizilir; okunabilirlik token çiftlerine dayanır.
@MainActor
struct GlassSurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?

    @Environment(\.colorScheme) private var colorScheme

    // Renkli (tint) yüzey neredeyse opak: üstündeki metin token çiftinin kontrastını korur.
    nonisolated static var tintOpacity: Double { 0.88 }
    // Renksiz yüzeyde vademSurface örtüsü. Arka plan sabit değil (siyah/beyaz dahil her zemin
    // olabilir); 0.86 textSecondary'yi en kötü zeminde de AA (4.5:1) üstünde tutar, hafif saydamlık kalır.
    nonisolated static var surfaceOpacity: Double { 0.86 }

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay {
                        shape
                            .fill(tint ?? Color.vademSurface)
                            .opacity(tint == nil ? Self.surfaceOpacity : Self.tintOpacity)
                    }
                    // Gölge yalnızca zeminde; metinlere gölge düşmez.
                    .shadow(color: shadowColor, radius: 12, x: 0, y: 4)
                    .accessibilityHidden(true)
            }
            .overlay {
                // İnce açık kenar: camın parlak kenarı.
                shape
                    .strokeBorder(borderColor, lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }

    private var borderColor: Color {
        Color.white.opacity(colorScheme == .dark ? 0.14 : 0.7)
    }

    private var shadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08)
    }
}

public extension View {
    /// Glass surface for cards, hero pills and the ＋ button, in `shape`: a translucent material,
    /// a thin light border and a soft shadow. Without `tint` the material is veiled with
    /// `vademSurface`; with `tint` (e.g. `vademAccent`) it is nearly opaque in that color,
    /// so the matching foreground token stays readable in light and dark.
    /// For floating controls (e.g. the tab bar) use ``vademGlass(in:)`` instead.
    func vademGlassSurface<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(GlassSurfaceModifier(shape: shape, tint: tint))
    }
}
