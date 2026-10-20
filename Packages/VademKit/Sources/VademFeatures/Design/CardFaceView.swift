import SwiftUI

/// A card face: the style's mesh gradient with a title and a subtitle.
///
/// The mesh drifts slowly; the drift stops under Reduce Motion or `-ui-static-motion`.
@MainActor
public struct CardFaceView: View {
    private let title: String
    private let subtitle: String
    private let style: CardStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(title: String, subtitle: String, style: CardStyle) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "creditcard.fill")
                .font(.title3)
                .accessibilityHidden(true)
            Spacer(minLength: 24)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.subheadline)
        }
        .foregroundStyle(style.foreground)
        // Sabit en-boy oranı yerine minimum yükseklik: büyük yazı boyutunda kart uzar, metin kırpılmaz.
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
        .padding(20)
        .background { mesh }
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var mesh: some View {
        // Reduce Motion veya UI kontrolünün -ui-static-motion argümanı: mesh sabit kalır.
        if !Motion.isAnimated(reduceMotion: reduceMotion, staticMotionRequested: Motion.staticMotionRequested) {
            MeshGradient(width: 3, height: 3, points: Self.points(at: 0), colors: style.meshColors)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: Self.points(at: context.date.timeIntervalSinceReferenceDate),
                    colors: style.meshColors
                )
            }
        }
    }

    // Köşeler sabit (gradyan kartı tam doldursun); kenar ortaları ve merkez yavaşça salınır.
    static func points(at time: TimeInterval) -> [SIMD2<Float>] {
        let phase = Float((time / Motion.meshDriftPeriod).truncatingRemainder(dividingBy: 1) * 2 * .pi)
        let amplitude: Float = 0.08
        let dx = amplitude * sin(phase)
        let dy = amplitude * cos(phase)
        return [
            [0, 0], [0.5 + dx, 0], [1, 0],
            [0, 0.5 + dy], [0.5 + dx, 0.5 - dy], [1, 0.5 - dy],
            [0, 1], [0.5 - dx, 1], [1, 1],
        ]
    }
}

#Preview {
    VStack(spacing: 16) {
        CardFaceView(title: "Everyday", subtitle: "Due on the 15th", style: .night)
        CardFaceView(title: "Travel", subtitle: "Due on the 2nd", style: .sunset)
    }
    .padding()
}
