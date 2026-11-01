import Testing
@testable import VademFeatures

@Suite("LaunchHandoff")
struct LaunchHandoffTests {
    struct ShownCase: CustomTestStringConvertible, Sendable {
        let reduceMotion: Bool
        let staticMotion: Bool
        let expected: Bool
        var testDescription: String { "reduce=\(reduceMotion) static=\(staticMotion) -> \(expected)" }
    }

    static let shownCases: [ShownCase] = [
        .init(reduceMotion: false, staticMotion: false, expected: true),
        .init(reduceMotion: true, staticMotion: false, expected: false),
        .init(reduceMotion: false, staticMotion: true, expected: false),
        .init(reduceMotion: true, staticMotion: true, expected: false),
    ]

    @Test("Overlay is shown only when motion runs", arguments: shownCases)
    func shownOnlyWithMotion(_ c: ShownCase) {
        #expect(LaunchHandoff.isShown(reduceMotion: c.reduceMotion, staticMotionRequested: c.staticMotion) == c.expected)
    }

    @Test("First frame matches the launch screen: opaque, natural logo size")
    func startIsOpaqueAndNatural() {
        #expect(LaunchHandoff.start == LaunchHandoff.State(opacity: 1, logoScale: 1))
    }

    @Test("Last frame is transparent and the logo is smaller")
    func endIsTransparentAndShrunk() {
        #expect(LaunchHandoff.end.opacity == 0)
        #expect(LaunchHandoff.end.logoScale < LaunchHandoff.start.logoScale)
        #expect(LaunchHandoff.end.logoScale > 0)
    }

    @Test("Transition is short: positive and at most about half a second")
    func durationIsShort() {
        #expect(LaunchHandoff.duration > 0)
        #expect(LaunchHandoff.duration <= 0.5)
    }
}
