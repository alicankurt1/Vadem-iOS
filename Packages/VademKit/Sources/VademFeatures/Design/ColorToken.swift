import SwiftUI

/// The Vadem color tokens. Each one is a color set with a light and a dark value
/// in the module's asset catalog; the raw value is the asset name.
public enum ColorToken: String, CaseIterable, Sendable {
    case background
    case surface
    case separator
    case hero
    case heroText
    case heroSecondary
    case accent
    case onAccent
    case textPrimary
    case textSecondary
    case brand
    case dueToday
    case dueTodayBackground
    case dueSoon
    case dueSoonBackground
    case dueLater
    case dueLaterBackground
    case paid
    case ambientHome
    case ambientAnalytics
    case ambientCards
    case ambientSettings

    /// The adaptive color for this token, loaded from `Bundle.module`.
    public var color: Color {
        Color(rawValue, bundle: .module)
    }
}

// Ekranlar token'ları `Color.vademBrand` gibi kısa adlarla kullanır.
public extension Color {
    /// App background.
    static var vademBackground: Color { ColorToken.background.color }
    /// Cards, sheets and grouped rows.
    static var vademSurface: Color { ColorToken.surface.color }
    /// Hairlines and borders.
    static var vademSeparator: Color { ColorToken.separator.color }
    /// Bold hero panel background.
    static var vademHero: Color { ColorToken.hero.color }
    /// Primary text on the hero panel.
    static var vademHeroText: Color { ColorToken.heroText.color }
    /// Secondary text on the hero panel.
    static var vademHeroSecondary: Color { ColorToken.heroSecondary.color }
    /// Accent fill (buttons, chips, highlights). Fill only, never use it as a text color;
    /// put `vademOnAccent` content on it.
    static var vademAccent: Color { ColorToken.accent.color }
    /// Text and icons on a `vademAccent` fill.
    static var vademOnAccent: Color { ColorToken.onAccent.color }
    /// Primary text.
    static var vademTextPrimary: Color { ColorToken.textPrimary.color }
    /// Secondary text.
    static var vademTextSecondary: Color { ColorToken.textSecondary.color }
    /// Brand color for text and links (deep teal).
    static var vademBrand: Color { ColorToken.brand.color }
    /// Foreground for payments due today.
    static var vademDueToday: Color { ColorToken.dueToday.color }
    /// Background for payments due today.
    static var vademDueTodayBackground: Color { ColorToken.dueTodayBackground.color }
    /// Foreground for payments due soon.
    static var vademDueSoon: Color { ColorToken.dueSoon.color }
    /// Background for payments due soon.
    static var vademDueSoonBackground: Color { ColorToken.dueSoonBackground.color }
    /// Foreground for payments due later.
    static var vademDueLater: Color { ColorToken.dueLater.color }
    /// Background for payments due later.
    static var vademDueLaterBackground: Color { ColorToken.dueLaterBackground.color }
    /// Paid state.
    static var vademPaid: Color { ColorToken.paid.color }
    /// Ambient background tint of the This month tab; text tokens keep AA contrast on it.
    static var vademAmbientHome: Color { ColorToken.ambientHome.color }
    /// Ambient background tint of the Analytics tab; text tokens keep AA contrast on it.
    static var vademAmbientAnalytics: Color { ColorToken.ambientAnalytics.color }
    /// Ambient background tint of the Cards tab; text tokens keep AA contrast on it.
    static var vademAmbientCards: Color { ColorToken.ambientCards.color }
    /// Ambient background tint of the Settings tab; text tokens keep AA contrast on it.
    static var vademAmbientSettings: Color { ColorToken.ambientSettings.color }
}
