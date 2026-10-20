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
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "creditcard.fill")
                .font(.title3)
                .accessibilityHidden(true)
                .padding([.top, .horizontal], 20)
            Spacer(minLength: 24)
            textBlock
        }
        .foregroundStyle(style.foreground)
        // Sabit en-boy oranı yerine minimum yükseklik: büyük yazı boyutunda kart uzar, metin kırpılmaz.
        .frame(maxWidth: .infinity, minHeight: 208, alignment: .leading)
        .background {
            // Hafif karartma: mesh'in açık bölgelerinde simge de okunur kalır.
            mesh.overlay(Self.scrim)
        }
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // Başlık ve alt başlık düz, opak bir şeridin üstünde: arkalarındaki renk her yazı boyutunda
    // ve her stilde tam olarak `textBackground` olur; kontrast hesaplanan değerle aynıdır.
    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding([.bottom, .horizontal], 20)
        .padding(.top, 8)
        .background(alignment: .top) {
            // Şeridin üstünde mesh'ten şeride yumuşak geçiş; metin her zaman opak kısımda kalır.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [style.textBackground.opacity(0), style.textBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Self.fadeHeight)
                style.textBackground
            }
            .padding(.top, -Self.fadeHeight)
        }
    }

    // Mesh'ten opak şeride geçişin yüksekliği.
    private static let fadeHeight: CGFloat = 32

    // Üstte hafif, alta doğru daha koyu.
    private static let scrim = LinearGradient(
        colors: [.black.opacity(0.15), .black.opacity(0.4)],
        startPoint: .top,
        endPoint: .bottom
    )

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
