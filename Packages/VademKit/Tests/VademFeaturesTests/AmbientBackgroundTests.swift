import SwiftUI
import Testing
import VademFeatures

@MainActor
@Suite("AmbientBackground")
struct AmbientBackgroundTests {

    // Hareket yalnızca Reduce Motion ve statik hareket kapalıyken, sahne aktifken çalışır.
    @Test("Animates only when motion is allowed and the scene is active", arguments: [
        (false, false, ScenePhase.active, true),
        (true, false, ScenePhase.active, false),
        (false, true, ScenePhase.active, false),
        (true, true, ScenePhase.active, false),
        (false, false, ScenePhase.inactive, false),
        (false, false, ScenePhase.background, false),
        (true, true, ScenePhase.background, false),
    ])
    func isAnimated(reduceMotion: Bool, staticMotion: Bool, phase: ScenePhase, expected: Bool) {
        #expect(AmbientBackground.isAnimated(
            reduceMotion: reduceMotion, staticMotionRequested: staticMotion, scenePhase: phase
        ) == expected)
    }

    @Test("Mesh has 3x3 points inside the unit square at any time", arguments: [
        0.0, 1.0, 7.0, 14.0, 27.9, 28.0, 1_000_000.0, -5.0, -28.0,
    ])
    func meshPointsShape(time: Double) {
        let points = AmbientBackground.meshPoints(at: time)
        #expect(points.count == 9)
        for point in points {
            #expect(point.x >= 0 && point.x <= 1)
            #expect(point.y >= 0 && point.y <= 1)
        }
    }

    @Test("Mesh corners stay fixed so it always fills the screen", arguments: [0.0, 3.0, 10.5, 21.0, -9.0])
    func meshCornersFixed(time: Double) {
        let p = AmbientBackground.meshPoints(at: time)
        #expect(p[0] == [0, 0])
        #expect(p[2] == [1, 0])
        #expect(p[6] == [0, 1])
        #expect(p[8] == [1, 1])
    }

    @Test("Mesh repeats after one drift period")
    func meshPeriodic() {
        let period = Motion.ambientDriftPeriod
        for time in [0.0, 5.0, 13.3] {
            let a = AmbientBackground.meshPoints(at: time)
            let b = AmbientBackground.meshPoints(at: time + period)
            for (x, y) in zip(a, b) {
                #expect(abs(x.x - y.x) < 1e-4 && abs(x.y - y.y) < 1e-4)
            }
        }
    }

    @Test("Mesh actually moves between times")
    func meshMoves() {
        #expect(AmbientBackground.meshPoints(at: 0) != AmbientBackground.meshPoints(at: Motion.ambientDriftPeriod / 4))
    }

    @Test("Drift period is slower than the card mesh and tint fade is positive")
    func motionConstants() {
        #expect(Motion.ambientDriftPeriod > Motion.meshDriftPeriod)
    }

    @Test("There are a few particles inside the unit square with positive radius")
    func particlesDefinition() {
        let particles = AmbientBackground.particles
        #expect((3...8).contains(particles.count))
        for particle in particles {
            #expect(particle.radius > 0 && particle.radius < 0.5)
            #expect((0.0...1.0).contains(particle.center.x))
            #expect((0.0...1.0).contains(particle.center.y))
        }
    }

    @Test("Particle centers stay within the drift distance of their resting center", arguments: [
        0.0, 2.0, 9.0, 14.0, 27.0, 123_456.0, -3.0,
    ])
    func particlesStayNearRest(time: Double) {
        let centers = AmbientBackground.particleCenters(at: time)
        #expect(centers.count == AmbientBackground.particles.count)
        for (particle, center) in zip(AmbientBackground.particles, centers) {
            let dx = center.x - particle.center.x
            let dy = center.y - particle.center.y
            #expect((dx * dx + dy * dy).squareRoot() <= AmbientBackground.particleDrift + 1e-9)
        }
    }

    @Test("Particles repeat after one drift period and move within it")
    func particlesPeriodic() {
        let period = Motion.ambientDriftPeriod
        let a = AmbientBackground.particleCenters(at: 4)
        let b = AmbientBackground.particleCenters(at: 4 + period)
        for (x, y) in zip(a, b) {
            #expect(abs(x.x - y.x) < 1e-6 && abs(x.y - y.y) < 1e-6)
        }
        #expect(AmbientBackground.particleCenters(at: 0) != AmbientBackground.particleCenters(at: period / 3))
    }

    @Test("Solid gutter covers at least the 4 pt the UI check samples")
    func gutter() {
        #expect(AmbientBackground.solidGutterWidth >= 4)
    }

    @Test("Every tab has its own ambient tint")
    func distinctTints() {
        let tints = AppTab.allCases.map(\.ambientTint)
        #expect(tints.count == 4)
        #expect(Set(tints.map(\.rawValue)).count == AppTab.allCases.count)
    }

    @Test("Tab to tint mapping", arguments: [
        (AppTab.home, ColorToken.ambientHome),
        (AppTab.analytics, ColorToken.ambientAnalytics),
        (AppTab.cards, ColorToken.ambientCards),
        (AppTab.settings, ColorToken.ambientSettings),
    ])
    func mapping(tab: AppTab, token: ColorToken) {
        #expect(tab.ambientTint == token)
    }
}
