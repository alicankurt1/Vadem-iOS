import Foundation
import SwiftUI

/// The short hand-off from the system launch screen to the app: the same background and logo,
/// which then fade out while the logo shrinks slightly.
///
/// The overlay is only shown when motion runs (``Motion/isAnimated(reduceMotion:staticMotionRequested:)``);
/// under Reduce Motion or `-ui-static-motion` the app's first frame is the app itself.
public enum LaunchHandoff {
    /// The look of the overlay (background and logo together).
    public struct State: Equatable, Sendable {
        /// Opacity of the whole overlay.
        public var opacity: Double
        /// Scale of the logo.
        public var logoScale: Double

        /// Creates a look with `opacity` and `logoScale`.
        public init(opacity: Double, logoScale: Double) {
            self.opacity = opacity
            self.logoScale = logoScale
        }
    }

    /// The first frame: identical to the system launch screen (fully opaque, logo at its natural size).
    public static let start = State(opacity: 1, logoScale: 1)
    /// The last frame: fully transparent, logo slightly smaller.
    public static let end = State(opacity: 0, logoScale: 0.85)

    /// Seconds from ``start`` to ``end``.
    public static let duration: Double = 0.45

    /// The animation from ``start`` to ``end``.
    public static let animation = Animation.easeOut(duration: duration)

    /// Whether the overlay is shown: only when motion runs (never under Reduce Motion or static motion).
    public static func isShown(reduceMotion: Bool, staticMotionRequested: Bool) -> Bool {
        Motion.isAnimated(reduceMotion: reduceMotion, staticMotionRequested: staticMotionRequested)
    }
}

/// Covers the content with the launch screen look, then fades it out and removes it (see ``LaunchHandoff``).
@MainActor
private struct LaunchHandoffModifier: ViewModifier {
    let background: Color
    let logo: Image

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Geçiş bir kez oynar; bittiğinde örtü hiyerarşiden çıkar.
    @State private var isFinished = false
    @State private var state = LaunchHandoff.start

    func body(content: Content) -> some View {
        // Kök içerik hemen yüklenir; örtü yalnızca üstte durur, içeriği bekletmez.
        content
            .overlay {
                if !isFinished, LaunchHandoff.isShown(
                    reduceMotion: reduceMotion,
                    staticMotionRequested: Motion.staticMotionRequested
                ) {
                    overlay
                }
            }
    }

    private var overlay: some View {
        // Sistem açılış ekranı görseli güvenli alan payı olmadan tam ekranın ortasına koyar; burada da öyle.
        ZStack {
            background
            logo
                .scaleEffect(state.logoScale)
        }
        .ignoresSafeArea()
        .opacity(state.opacity)
        // Örtü dokunuşları ve VoiceOver'ı hiçbir zaman engellemez.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(LaunchHandoff.animation) {
                state = LaunchHandoff.end
            } completion: {
                // Animasyon bitince örtü kaldırılır; uygulama boşta kalır.
                isFinished = true
            }
        }
    }
}

public extension View {
    /// Covers this view with `background` and the centered `logo` (the launch screen look), then fades the cover
    /// out in ``LaunchHandoff/duration`` seconds while the logo shrinks slightly, and removes it.
    ///
    /// This view loads right away underneath. The cover never takes touches and is hidden from accessibility.
    /// Under Reduce Motion or `-ui-static-motion` there is no cover at all.
    func launchHandoff(background: Color, logo: Image) -> some View {
        modifier(LaunchHandoffModifier(background: background, logo: logo))
    }
}
