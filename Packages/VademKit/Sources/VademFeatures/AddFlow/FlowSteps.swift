import Foundation

/// The ordered steps of an add flow and which one is showing; one decision per step.
///
/// Pure value: the view that owns it calls ``advance()`` after a decision (e.g. right after a chip
/// is chosen) and ``goBack()`` for the back button, wrapping the call in a ``Motion`` animation.
public struct FlowSteps<Step: Hashable & Sendable>: Sendable, Equatable {
    /// Every step, in order; never empty.
    public let steps: [Step]
    /// The index of ``current`` in ``steps``.
    public private(set) var index: Int

    /// Starts at `start` when it is one of `steps`, otherwise at the first step.
    /// `steps` must not be empty.
    public init(_ steps: [Step], startingAt start: Step? = nil) {
        precondition(!steps.isEmpty, "A flow needs at least one step")
        self.steps = steps
        // Bilinmeyen başlangıç adımı ilk adıma düşer.
        self.index = start.flatMap { steps.firstIndex(of: $0) } ?? 0
    }

    /// The step that is showing.
    public var current: Step { steps[index] }

    /// The 1-based number of ``current`` ("Step 2 of 3").
    public var number: Int { index + 1 }

    /// How many steps the flow has.
    public var count: Int { steps.count }

    /// `true` on the first step (no back step inside the flow).
    public var isFirst: Bool { index == 0 }

    /// `true` on the last step (nothing to advance to).
    public var isLast: Bool { index == steps.count - 1 }

    /// Moves to the next step; returns `false` (and stays) on the last step.
    @discardableResult
    public mutating func advance() -> Bool {
        guard !isLast else { return false }
        index += 1
        return true
    }

    /// Moves to the previous step; returns `false` (and stays) on the first step.
    @discardableResult
    public mutating func goBack() -> Bool {
        guard !isFirst else { return false }
        index -= 1
        return true
    }
}
