import SwiftUI

/// A calm, living screen background: a slowly drifting mesh gradient between `vademBackground`
/// and a tint token, with a few soft floating light particles. Content and glass cards float above it.
///
/// Every color on it is a mix of `vademBackground` and `tint`, so a text token that keeps AA contrast
/// on both keeps it everywhere on the background. The left ``solidGutterWidth`` points stay plain
/// `vademBackground`. Changing `tint` cross-fades (no animation under Reduce Motion or
/// `-ui-static-motion`). Motion runs only while ``isAnimated(reduceMotion:staticMotionRequested:scenePhase:)``
/// is `true`; otherwise the frame at time 0 is shown. Hidden from accessibility, never hit-tested.
@MainActor
public struct AmbientBackground: View {
    private let tint: ColorToken

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// Creates the background tinted with `tint` (e.g. ``AppTab/ambientTint``).
    public init(tint: ColorToken) {
        self.tint = tint
    }

    /// Width of the plain `vademBackground` strip at the left edge (the UI check samples the left 4 pt).
    public static let solidGutterWidth: CGFloat = 8

    // Sol şeritten sonra ambiyansın yumuşakça belirdiği genişlik.
    private static let gutterFadeWidth: CGFloat = 40

    /// Whether the background moves: not under Reduce Motion or `-ui-static-motion`, and only
    /// while the scene is active (no work in the background).
    public static func isAnimated(reduceMotion: Bool, staticMotionRequested: Bool, scenePhase: ScenePhase) -> Bool {
        Motion.isAnimated(reduceMotion: reduceMotion, staticMotionRequested: staticMotionRequested)
            && scenePhase == .active
    }

    public var body: some View {
        ZStack {
            Color.vademBackground
            ambient
                // Her renk ayrı bir katman: renk değişince eskisi silinir, yenisi belirir.
                .id(tint)
                .transition(.opacity)
                .mask { gutterMask }
        }
        .animation(Motion.animation(Motion.ambientTint, reduceMotion: reduceMotion), value: tint)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // Sol kenarda düz zemin, sonra yumuşak geçiş; sağdan sola dillerde de ekranın solunda kalır.
    private var gutterMask: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.solidGutterWidth)
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.gutterFadeWidth)
            Color.black
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder
    private var ambient: some View {
        let animated = Self.isAnimated(
            reduceMotion: reduceMotion, staticMotionRequested: Motion.staticMotionRequested, scenePhase: scenePhase
        )
        if animated {
            // Yavaş bir sahne için 30 fps yeterli; pil dostu.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                frame(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            // Hareket kapalı ya da uygulama arka planda: sabit kare, hiç iş yok.
            frame(at: 0)
        }
    }

    private func frame(at time: TimeInterval) -> some View {
        let base = Color.vademBackground
        let tintColor = tint.color
        let middle = base.mix(with: tintColor, by: 0.5)
        return MeshGradient(
            width: 3,
            height: 3,
            points: Self.meshPoints(at: time),
            colors: [
                tintColor, middle, base,
                middle, tintColor, middle,
                base, middle, tintColor,
            ]
        )
        .overlay {
            Canvas { context, size in
                Self.drawParticles(in: &context, size: size, at: time, color: tintColor)
            }
        }
    }

    /// The 3×3 mesh points at `time` (unit square). Corners are fixed so the mesh always fills
    /// the screen; edge midpoints move along their edge and the center drifts, one cycle per
    /// ``Motion/ambientDriftPeriod``.
    public static func meshPoints(at time: TimeInterval) -> [SIMD2<Float>] {
        let phase = Float(cyclePhase(at: time))
        let amplitude: Float = 0.12
        let dx = amplitude * sin(phase)
        let dy = amplitude * cos(phase)
        return [
            [0, 0], [0.5 + dx, 0], [1, 0],
            [0, 0.5 - dy], [0.5 - dx, 0.5 + dy], [1, 0.5 + dy],
            [0, 1], [0.5 + dx, 1], [1, 1],
        ]
    }

    /// One floating light: a soft radial glow around ``center``.
    public struct Particle: Sendable, Equatable {
        /// Resting center in the unit square.
        public let center: SIMD2<Double>
        /// Glow radius as a fraction of the shorter screen side.
        public let radius: Double
        /// Phase offset of the particle's orbit, in radians.
        public let phase: Double
    }

    /// The particles: few, large and soft.
    public static let particles: [Particle] = [
        Particle(center: [0.25, 0.18], radius: 0.30, phase: 0),
        Particle(center: [0.80, 0.30], radius: 0.22, phase: 1.3),
        Particle(center: [0.35, 0.55], radius: 0.26, phase: 2.6),
        Particle(center: [0.75, 0.72], radius: 0.32, phase: 3.9),
        Particle(center: [0.30, 0.90], radius: 0.20, phase: 5.2),
    ]

    /// How far (unit square) a particle drifts from its resting center.
    public static let particleDrift: Double = 0.06

    /// Particle centers at `time` in the unit square: each orbits its resting center by
    /// ``particleDrift``, one cycle per ``Motion/ambientDriftPeriod``.
    public static func particleCenters(at time: TimeInterval) -> [SIMD2<Double>] {
        let phase = cyclePhase(at: time)
        return particles.map { particle in
            particle.center + particleDrift * SIMD2(cos(phase + particle.phase), sin(phase + particle.phase))
        }
    }

    // Döngüdeki açı (0..<2π); negatif zamanda da aynı aralıkta kalır.
    private static func cyclePhase(at time: TimeInterval) -> Double {
        var fraction = (time / Motion.ambientDriftPeriod).truncatingRemainder(dividingBy: 1)
        if fraction < 0 { fraction += 1 }
        return fraction * 2 * .pi
    }

    // Bulanıklaştırma yerine radyal gradyan: aynı yumuşak ışık, çok daha ucuz. Renk tint olduğu için
    // zemin hep arka plan ile tint arasında kalır (kontrast güvencesi bozulmaz).
    private static func drawParticles(in context: inout GraphicsContext, size: CGSize, at time: TimeInterval, color: Color) {
        let side = min(size.width, size.height)
        for (particle, center) in zip(particles, particleCenters(at: time)) {
            let point = CGPoint(x: center.x * size.width, y: center.y * size.height)
            let radius = particle.radius * side
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(0.8), color.opacity(0)]),
                    center: point, startRadius: 0, endRadius: radius
                )
            )
        }
    }
}

public extension AppTab {
    /// The tint token of this tab's ``AmbientBackground``.
    var ambientTint: ColorToken {
        switch self {
        case .home: return .ambientHome
        case .analytics: return .ambientAnalytics
        case .cards: return .ambientCards
        case .settings: return .ambientSettings
        }
    }
}

#Preview {
    AmbientBackground(tint: .ambientHome)
}
