import Foundation
import SwiftUI

/// Shared animation constants and the single place that decides whether motion runs.
///
/// Every animated effect (tab switch, staggered entry, progress fill) is gated by
/// ``isAnimated(reduceMotion:staticMotionRequested:)``: under Reduce Motion or ``staticMotionArgument``
/// views are in their final state right away (fully opaque, no blur, scale or offset, full fill).
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

    // MARK: - Sekme geçişi

    /// The look of the tab content during a tab switch: a small horizontal offset and a partial fade.
    public struct TabSwitchState: Equatable, Sendable {
        /// Horizontal offset (points) of the content; positive is toward the trailing side.
        public var offsetX: Double
        /// Opacity of the content.
        public var opacity: Double

        /// Creates a look with `offsetX` points of offset and `opacity`.
        public init(offsetX: Double, opacity: Double) {
            self.offsetX = offsetX
            self.opacity = opacity
        }

        /// The settled look: no offset, fully opaque.
        public static let settled = TabSwitchState(offsetX: 0, opacity: 1)
    }

    /// Points the incoming tab starts away from its place.
    public static let tabSwitchOffset: Double = 10
    /// Opacity the incoming tab starts at; high, so the background never shows through as a flash.
    public static let tabSwitchStartOpacity: Double = 0.9
    /// Seconds the incoming tab takes to settle.
    public static let tabSwitchDuration: Double = 0.22

    /// Where the incoming tab starts when switching `from` → `to`: a later tab (in ``AppTab/allCases`` order)
    /// comes from the trailing side, an earlier one from the leading side; the same tab is ``TabSwitchState/settled``.
    ///
    /// The content is swapped at once and settles from this look to ``TabSwitchState/settled`` in
    /// ``tabSwitchDuration`` seconds, so no frame is ever blank.
    public static func tabSwitchStart(from: AppTab, to: AppTab) -> TabSwitchState {
        let order = AppTab.allCases
        guard let fromIndex = order.firstIndex(of: from), let toIndex = order.firstIndex(of: to),
              fromIndex != toIndex else { return .settled }
        let direction: Double = toIndex > fromIndex ? 1 : -1
        return TabSwitchState(offsetX: direction * tabSwitchOffset, opacity: tabSwitchStartOpacity)
    }

    // MARK: - Kademeli giriş

    /// The place of an element in a screen's staggered entry: header first, then hero, then list.
    public enum EntryOrder: Int, CaseIterable, Comparable, Sendable {
        /// The screen's header (e.g. the month bar).
        case header = 0
        /// The hero (e.g. the total panel or the chart).
        case hero = 1
        /// The list below.
        case list = 2

        public static func < (lhs: EntryOrder, rhs: EntryOrder) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// The look of an element while it enters.
    public struct EntryState: Equatable, Sendable {
        /// Opacity of the element.
        public var opacity: Double
        /// Vertical offset (points) of the element.
        public var offsetY: Double
        /// Scale of the element.
        public var scale: Double

        /// The final, settled look: fully shown, no offset, no scale.
        public static let settled = EntryState(opacity: 1, offsetY: 0, scale: 1)
        /// The look before the entry animation starts.
        public static let hidden = EntryState(opacity: 0, offsetY: 12, scale: 0.98)
    }

    /// Seconds one element takes to enter.
    public static let entryDuration: Double = 0.35
    /// Seconds between the entries of two consecutive ``EntryOrder`` steps.
    public static let entryStagger: Double = 0.06

    /// Seconds an element of `order` waits before it enters: `0` for the header, growing by ``entryStagger``.
    public static func entryDelay(order: EntryOrder) -> Double {
        Double(order.rawValue) * entryStagger
    }

    /// The entry animation of an element of `order` (delayed by ``entryDelay(order:)``).
    public static func entryAnimation(order: EntryOrder) -> Animation {
        .smooth(duration: entryDuration).delay(entryDelay(order: order))
    }

    /// The look of an entering element: ``EntryState/settled`` once it `hasEntered` or when motion is off,
    /// otherwise ``EntryState/hidden``. Static mode never starts hidden, so the app is idle and fully visible.
    public static func entryState(hasEntered: Bool, isAnimated: Bool) -> EntryState {
        hasEntered || !isAnimated ? .settled : .hidden
    }

    // MARK: - Doluluk

    /// The fill animation of progress bars.
    public static let fill = Animation.smooth(duration: 0.6)

    /// The drawn share of a bar's `value`: `value` once it `hasAppeared` or when motion is off, otherwise `0`.
    public static func fillFraction(_ value: Double, hasAppeared: Bool, isAnimated: Bool) -> Double {
        hasAppeared || !isAnimated ? value : 0
    }
}

/// Plays the staggered entry of an element the first time it appears (see ``Motion/EntryOrder``).
@MainActor
private struct MotionEntryModifier: ViewModifier {
    let order: Motion.EntryOrder

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Ekranın girişi bittiyse (bkz. motionEntryScope) sonradan oluşan görünümler doğrudan görünür.
    @Environment(\.motionEntryFinished) private var entryFinished
    // İlk görünüşte bir kez oynar; sekme canlı kaldığı için sonraki görünüşlerde tekrar etmez.
    @State private var hasEntered = false

    func body(content: Content) -> some View {
        let isAnimated = Motion.isAnimated(reduceMotion: reduceMotion, staticMotionRequested: Motion.staticMotionRequested)
        let state = Motion.entryState(hasEntered: hasEntered || entryFinished, isAnimated: isAnimated)
        // Görünüm hiyerarşiden çıkarılmaz; yalnızca saydamlık, kayma ve ölçek değişir.
        content
            .opacity(state.opacity)
            .scaleEffect(state.scale)
            .offset(y: state.offsetY)
            .onAppear {
                guard !hasEntered else { return }
                // Giriş zaten oynadıysa (yeni eklenen kart, ay değişimi, dal değişimi) animasyon yok.
                if isAnimated, !entryFinished {
                    withAnimation(Motion.entryAnimation(order: order)) { hasEntered = true }
                } else {
                    hasEntered = true
                }
            }
    }
}

extension EnvironmentValues {
    // Ekranın kademeli girişi bitti mi; `motionEntryScope` yazar, `MotionEntryModifier` okur.
    @Entry var motionEntryFinished = false
}

/// Owns the "entry has played" flag of one screen (see `motionEntryScope()`).
@MainActor
private struct MotionEntryScopeModifier: ViewModifier {
    // Ekranın ilk görünüşündeki giriş bitince true olur ve ekran yaşadıkça öyle kalır.
    @State private var isFinished = false

    func body(content: Content) -> some View {
        content
            .environment(\.motionEntryFinished, isFinished)
            .task {
                guard !isFinished else { return }
                // En son giren adımın (liste) gecikmesi ve süresi kadar beklenir; bu arada oluşan
                // görünümler de girişe katılır, sonrakiler doğrudan görünür.
                let total = Motion.entryDelay(order: .list) + Motion.entryDuration
                try? await Task.sleep(for: .seconds(total))
                guard !Task.isCancelled else { return }
                isFinished = true
            }
    }
}

/// Settles the tab content from `start` to ``Motion/TabSwitchState/settled`` each time `trigger` changes.
@MainActor
private struct TabSwitchModifier: ViewModifier {
    let start: Motion.TabSwitchState
    let trigger: Int

    func body(content: Content) -> some View {
        // Efekt `if` ile eklenip kaldırılmaz: dal değişimi TabView'in kimliğini değiştirir ve sekmelerin
        // yığınları ile kaydırma konumları sıfırlanır. Yerleşik durumda kayma 0, saydamlık 1'dir (etkisiz).
        let start = start
        return content
            .keyframeAnimator(initialValue: Motion.TabSwitchState.settled, trigger: trigger) { content, state in
                content
                    .opacity(state.opacity)
                    .offset(x: state.offsetX)
            } keyframes: { _ in
                // Her tetiklemede başlangıca atlanır ve oradan yerine oturulur; art arda dokunuşlarda
                // animasyon baştan başlar, son seçilen sekmede biter.
                KeyframeTrack(\.offsetX) {
                    MoveKeyframe(start.offsetX)
                    LinearKeyframe(0, duration: Motion.tabSwitchDuration, timingCurve: .easeOut)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(start.opacity)
                    LinearKeyframe(1, duration: Motion.tabSwitchDuration, timingCurve: .easeOut)
                }
            }
    }
}

public extension View {
    /// Fades and slides this view in the first time it appears, after the delay of its `order`.
    ///
    /// Under Reduce Motion or `-ui-static-motion` the view is shown in its final state at once.
    /// The view stays in the hierarchy (and hittable) the whole time.
    func motionEntry(order: Motion.EntryOrder) -> some View {
        modifier(MotionEntryModifier(order: order))
    }

    /// Marks this view as a screen whose ``motionEntry(order:)`` elements play only on its first appearance.
    ///
    /// Elements created after that entry (a card added later, a month or branch change) just appear.
    func motionEntryScope() -> some View {
        modifier(MotionEntryScopeModifier())
    }

    /// Plays the tab-switch settle each time `trigger` changes: from `start` to ``Motion/TabSwitchState/settled``
    /// in ``Motion/tabSwitchDuration`` seconds (ease out). A new `trigger` restarts it from its new `start`.
    ///
    /// The effect is always applied (never added or removed), so the view's identity is kept; at rest it has no effect.
    /// Leave `trigger` unchanged under Reduce Motion or `-ui-static-motion` for an instant switch.
    func tabSwitchEffect(from start: Motion.TabSwitchState, trigger: Int) -> some View {
        modifier(TabSwitchModifier(start: start, trigger: trigger))
    }
}
