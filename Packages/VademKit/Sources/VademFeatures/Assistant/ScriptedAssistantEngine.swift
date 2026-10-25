import Foundation
import Synchronization

/// A fake ``AssistantEngine`` for tests and UI sample data: answers from a script, records questions.
public final class ScriptedAssistantEngine: AssistantEngine {
    /// What the fake does for the next question.
    public enum Step: Sendable {
        /// Answers with this reply.
        case reply(AssistantReply)
        /// Throws this error.
        case throwing(any Error & Sendable)
    }

    private struct State {
        var steps: [Step]
        var questions: [String] = []
    }

    public let availability: AssistantAvailability
    private let fallback: AssistantReply
    private let state: Mutex<State>

    /// Creates a fake. Steps are used in order; when they run out `fallback` answers.
    public init(
        availability: AssistantAvailability = .available,
        steps: [Step] = [],
        fallback: AssistantReply = .text("OK")
    ) {
        self.availability = availability
        self.fallback = fallback
        self.state = Mutex(State(steps: steps))
    }

    /// The questions asked so far, oldest first.
    public var questions: [String] { state.withLock { $0.questions } }

    public func respond(to question: String) async throws -> AssistantReply {
        let step: Step? = state.withLock {
            $0.questions.append(question)
            return $0.steps.isEmpty ? nil : $0.steps.removeFirst()
        }
        switch step {
        case .reply(let reply): return reply
        case .throwing(let error): throw error
        case nil: return fallback
        }
    }
}
