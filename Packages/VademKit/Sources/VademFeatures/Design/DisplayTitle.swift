import SwiftUI

/// A large editorial title in the system serif (New York) with one accented phrase in italic
/// `vademBrand`, e.g. "You pay *₺4.825,50*".
///
/// The whole title is one `Text`, so VoiceOver reads it as a single header (never split at the
/// accent). It wraps freely and grows with Dynamic Type up to AX5 (no line limit, no fixed height).
@MainActor
public struct DisplayTitle: View {
    private let title: String
    private let accent: String?
    private let spokenLabel: String?
    private let identifier: String?

    /// Creates a title; the first occurrence of `accent` in `title` is drawn italic in the accent text color.
    ///
    /// `accessibilityLabel` replaces what VoiceOver reads (e.g. a spoken amount instead of "₺");
    /// `identifier` becomes the title's accessibility identifier.
    public init(_ title: String, accent: String? = nil, accessibilityLabel: String? = nil, identifier: String? = nil) {
        self.title = title
        self.accent = accent
        self.spokenLabel = accessibilityLabel
        self.identifier = identifier
    }

    public var body: some View {
        Text(Self.styled(title, accent: accent))
            .font(Self.font)
            .foregroundStyle(Color.vademTextPrimary)
            .multilineTextAlignment(.leading)
            // Satır sınırı yok: AX5'te de alt satıra sarılır, kırpılmaz.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Text(spokenLabel ?? title))
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier ?? "")
    }

    // Sistem serif yazısı (New York); metin stiliyle Dynamic Type'a göre büyür.
    static let font = Font.system(.largeTitle, design: .serif, weight: .semibold)

    /// The range of `accent` in `title` (its first occurrence), or `nil` when it is empty or missing.
    nonisolated static func accentRange(in title: String, accent: String?) -> Range<String.Index>? {
        guard let accent, !accent.isEmpty else { return nil }
        return title.range(of: accent)
    }

    // Tek bir AttributedString: vurgu yalnızca biçim, öğe sınırı değil.
    // Vurgu rengi metin için güvenli `vademBrand` (vademAccent yalnızca dolgu rengidir).
    static func styled(_ title: String, accent: String?) -> AttributedString {
        var attributed = AttributedString(title)
        guard let accent, accentRange(in: title, accent: accent) != nil,
              let range = attributed.range(of: accent) else { return attributed }
        attributed[range].font = font.italic()
        attributed[range].foregroundColor = Color.vademBrand
        return attributed
    }
}

/// A small uppercase, letter-spaced label shown above a display or section title, e.g. "THIS MONTH".
///
/// Only the drawing is uppercased; VoiceOver reads the original text.
@MainActor
public struct EyebrowLabel: View {
    private let text: String

    /// Creates a label showing `text` in uppercase.
    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1.5)
            .foregroundStyle(Color.vademTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A screen header: an ``EyebrowLabel`` above a ``DisplayTitle``.
@MainActor
public struct DisplayHeader: View {
    private let eyebrow: String
    private let title: DisplayTitle

    /// Creates a header; see ``DisplayTitle/init(_:accent:accessibilityLabel:identifier:)`` for the title parameters.
    public init(
        eyebrow: String, title: String, accent: String? = nil,
        accessibilityLabel: String? = nil, identifier: String? = nil
    ) {
        self.eyebrow = eyebrow
        self.title = DisplayTitle(title, accent: accent, accessibilityLabel: accessibilityLabel, identifier: identifier)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            EyebrowLabel(eyebrow)
            title
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    VStack(spacing: 24) {
        DisplayHeader(eyebrow: "This month", title: "You pay ₺4.825,50", accent: "₺4.825,50")
        DisplayHeader(eyebrow: "Analytics", title: "Your next 12 months", accent: "12 months")
    }
    .padding()
    .background(Color.vademBackground)
}
