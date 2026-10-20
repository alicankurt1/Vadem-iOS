import SwiftUI

/// The Vadem color tokens. Each one is a color set with a light and a dark value
/// in the module's asset catalog; the raw value is the asset name.
public enum ColorToken: String, CaseIterable, Sendable {
    case background
    case surface
    case separator
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
    /// Primary text.
    static var vademTextPrimary: Color { ColorToken.textPrimary.color }
    /// Secondary text.
    static var vademTextSecondary: Color { ColorToken.textSecondary.color }
    /// Brand accent (ink violet).
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
}
