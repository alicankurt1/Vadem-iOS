import SwiftUI
import VademCore

/// The bold "this month" panel: a title, the total, a paid-progress bar with a caption
/// and a slot for action pills (``HeroPill``).
@MainActor
public struct HeroPanel<Actions: View>: View {
    private let title: String
    private let total: Money
    private let paid: Money
    private let captionPrefix: String
    private let summaryIdentifier: String?
    private let actions: Actions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates a panel showing `paid` of `total`, with `actions` (usually ``HeroPill`` buttons) below.
    ///
    /// The caption reads `"<captionPrefix> ₺1.200,00 of ₺4.825,50"`, e.g. `"Due so far …"` on Home.
    /// `summaryIdentifier` is the accessibility identifier of the summary (title, total, caption),
    /// a single header element.
    public init(
        title: String,
        total: Money,
        paid: Money,
        captionPrefix: String = HeroPanel.defaultCaptionPrefix,
        summaryIdentifier: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.total = total
        self.paid = paid
        self.captionPrefix = captionPrefix
        self.summaryIdentifier = summaryIdentifier
        self.actions = actions()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary
            actionStack
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vademHero, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // Başlık, toplam, çubuk ve açıklama VoiceOver'da tek öğe; tutarlar "₺" yerine okunabilir.
    // Uzun okunan etiket kısa açıklama metninin üstünde olsaydı denetim onu metnin çerçevesiyle
    // ölçüp "kırpılmış" sayıyordu; 8 pt'lik çubuğun üstünde ise "dokunma alanı küçük" sayıyordu.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.vademHeroText)
            AmountText(total)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Color.vademHeroText)
            progressBar
            Text(Self.caption(paid: paid, total: total, prefix: captionPrefix))
                .font(.footnote)
                .foregroundStyle(Color.vademHeroSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilitySummary(
            title: title, paid: paid, total: total, captionPrefix: captionPrefix
        ))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier(summaryIdentifier ?? "")
    }

    // Çubuk yalnızca görsel; bilgisi özet etiketinde.
    private var progressBar: some View {
        let value = Self.progress(paid: paid, total: total)
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.vademHeroSecondary.opacity(0.3))
                Capsule()
                    .fill(Color.vademAccent)
                    .frame(width: proxy.size.width * value)
            }
        }
        .frame(height: 8)
        // Reduce Motion veya -ui-static-motion açıkken çubuk animasyonsuz değişir.
        .animation(Motion.animation(Motion.amount, reduceMotion: reduceMotion), value: value)
    }

    // Düğmeler normalde yan yana, erişilebilirlik boyutlarında alt alta durur.
    private var actionStack: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            actions
        }
        .padding(.top, 4)
    }

    /// The caption's default first word: `"Paid"`.
    public nonisolated static var defaultCaptionPrefix: String { "Paid" }

    /// The share of `total` already paid, clamped to `0...1`.
    ///
    /// Pure: a zero or negative total and a negative paid amount give `0`, overpaying gives `1`.
    /// The ratio is computed in `Decimal`; only the result is a `Double` (for drawing).
    public nonisolated static func progress(paid: Money, total: Money) -> Double {
        guard total.amount > 0, paid.amount > 0 else { return 0 }
        guard paid < total else { return 1 }
        let ratio = paid.amount / total.amount
        return min(max(NSDecimalNumber(decimal: ratio).doubleValue, 0), 1)
    }

    // Görünen açıklama: "Paid ₺1.200,00 of ₺4.825,50" (ön ek değiştirilebilir, örn. "Due so far").
    nonisolated static func caption(paid: Money, total: Money, prefix: String = defaultCaptionPrefix) -> String {
        prefix + " " + AmountText.format(paid) + " of " + AmountText.format(total)
    }

    // Okunan açıklama: "Paid 1.200,00 Türk lirası of 4.825,50 Türk lirası".
    nonisolated static func spokenCaption(paid: Money, total: Money, prefix: String = defaultCaptionPrefix) -> String {
        prefix + " " + AmountText.spokenLabel(paid) + " of " + AmountText.spokenLabel(total)
    }

    // Panelin okunan özeti: "This month, 4.825,50 Türk lirası, Paid 1.200,00 Türk lirası of 4.825,50 Türk lirası".
    nonisolated static func accessibilitySummary(
        title: String, paid: Money, total: Money, captionPrefix: String = defaultCaptionPrefix
    ) -> String {
        [title, AmountText.spokenLabel(total), spokenCaption(paid: paid, total: total, prefix: captionPrefix)]
            .joined(separator: ", ")
    }
}

public extension HeroPanel where Actions == EmptyView {
    /// Creates a panel without action pills.
    init(title: String, total: Money, paid: Money, captionPrefix: String = HeroPanel.defaultCaptionPrefix) {
        self.init(title: title, total: total, paid: paid, captionPrefix: captionPrefix) { EmptyView() }
    }
}

#Preview {
    HeroPanel(title: "This month", total: Money(Decimal(482_550) / 100), paid: Money(1_200)) {
        Button("Add") {}.buttonStyle(.heroPill)
        Button("Calendar") {}.buttonStyle(.heroPill)
    }
    .padding()
}
