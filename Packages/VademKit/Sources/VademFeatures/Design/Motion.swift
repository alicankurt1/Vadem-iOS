import Foundation
import SwiftUI

/// Shared animation constants and the single place that decides whether motion runs.
public enum Motion {
    /// Small state changes (chips, toggles).
    public static let quick = Animation.snappy(duration: 0.25)
    /// Changing amounts (with the numeric-text transition).
    public static let amount = Animation.smooth(duration: 0.4)
    /// Seconds for one full cycle of the card mesh drift.
    public static let meshDriftPeriod: Double = 14
    /// Seconds for one full cycle of the ambient background drift (slower than the cards).
    public static let ambientDriftPeriod: Double = 28
    /// Cross-fade between two tab tints of the ambient background.
    public static let ambientTint = Animation.easeInOut(duration: 0.6)

    /// The launch argument the UI check passes to stop continuous animations.
    public static let staticMotionArgument = "-ui-static-motion"

    /// `true` when the app was launched with ``staticMotionArgument``.
    public static let staticMotionRequested = ProcessInfo.processInfo.arguments.contains(staticMotionArgument)

    /// Whether motion should run: never under Reduce Motion or when static motion is requested.
    public static func isAnimated(reduceMotion: Bool, staticMotionRequested: Bool) -> Bool {
        !reduceMotion && !staticMotionRequested
    }

    /// `animation` when ``isAnimated(reduceMotion:staticMotionRequested:)`` is `true`, otherwise `nil`.
    public static func animation(
        _ animation: Animation,
        reduceMotion: Bool,
        staticMotionRequested: Bool = Motion.staticMotionRequested
    ) -> Animation? {
        isAnimated(reduceMotion: reduceMotion, staticMotionRequested: staticMotionRequested) ? animation : nil
    }
}
