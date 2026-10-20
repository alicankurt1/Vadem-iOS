import SwiftUI

/// Shared animation constants. Callers pass `nil` instead when Reduce Motion is on.
public enum Motion {
    /// Small state changes (chips, toggles).
    public static let quick = Animation.snappy(duration: 0.25)
    /// Changing amounts (with the numeric-text transition).
    public static let amount = Animation.smooth(duration: 0.4)
    /// Seconds for one full cycle of the card mesh drift.
    public static let meshDriftPeriod: Double = 14

    /// `animation`, or `nil` when Reduce Motion is on.
    public static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
