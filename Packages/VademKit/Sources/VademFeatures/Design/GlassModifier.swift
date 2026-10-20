import SwiftUI

// Sadece yüzen kontroller için: iOS 26+'da Liquid Glass, daha eskide materyal.
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
    /// Uses `glassEffect` on iOS 26+ and a material on iOS 18–25.
    func vademGlass() -> some View {
        modifier(GlassModifier(shape: Capsule()))
    }

    /// Glass background for floating controls only, in `shape`.
    /// Uses `glassEffect` on iOS 26+ and a material on iOS 18–25.
    func vademGlass<S: Shape>(in shape: S) -> some View {
        modifier(GlassModifier(shape: shape))
    }
}
