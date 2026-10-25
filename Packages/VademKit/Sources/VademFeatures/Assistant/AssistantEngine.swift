import Foundation

/// Why the assistant cannot answer right now.
public enum AssistantUnavailableReason: Sendable, Hashable {
    /// The device cannot run the on-device model.
    case deviceNotEligible
    /// Apple Intelligence is switched off in Settings.
    case appleIntelligenceDisabled
    /// The model is still downloading or preparing.
    case modelNotReady
    /// Any other (or future) reason.
    case unknown
}

/// Whether the assistant can answer.
public enum AssistantAvailability: Sendable, Hashable {
    /// Ready to answer.
    case available
    /// The OS supports the model but it cannot run now.
    case unavailable(AssistantUnavailableReason)
    /// The OS is older than iOS 26: there is no on-device model at all.
    case unsupportedOS
}

/// Why a question got no answer; decides the friendly message.
public enum AssistantFailureKind: Sendable, Hashable {
    /// The model's safety guardrails refused the question or the answer.
    case guardrailViolation
    /// The conversation grew past the model's context window.
    case contextWindowExceeded
    /// The request was cancelled.
    case cancelled
    /// The assistant is not available (see ``AssistantAvailability``).
    case unavailable
    /// Anything else.
    case other
}

/// A friendly, user-facing failure: never an error type, so the UI just shows ``message``.
public struct AssistantFailure: Sendable, Hashable {
    /// What went wrong, for logic and tests.
    public let kind: AssistantFailureKind
    /// A short sentence for the user.
    public let message: String

    /// The standard failure for `kind`; ``message`` comes from the string catalog.
    public init(kind: AssistantFailureKind) {
        self.kind = kind
        switch kind {
        case .guardrailViolation:
            message = String(
                localized: "I can't help with that. Try asking about your payments in a different way.", bundle: .module
            )
        case .contextWindowExceeded:
            message = String(localized: "That question was too long for me. Try a shorter one.", bundle: .module)
        case .cancelled:
            message = String(localized: "Cancelled.", bundle: .module)
        case .unavailable:
            message = String(localized: "The assistant is not available on this device right now.", bundle: .module)
        case .other:
            message = String(localized: "Something went wrong. Please try again.", bundle: .module)
        }
    }
}

/// The assistant's answer to one question: text, or a friendly failure.
public enum AssistantReply: Sendable, Hashable {
    /// The answer.
    case text(String)
    /// No answer; show the message.
    case failure(AssistantFailure)
}

/// Answers questions about the user's payments. The app and tests only see this protocol,
/// never FoundationModels.
public protocol AssistantEngine: Sendable {
    /// Whether ``respond(to:)`` can answer now.
    var availability: AssistantAvailability { get }

    /// Answers `question`. Session problems come back as ``AssistantReply/failure(_:)``;
    /// only unexpected errors throw.
    func respond(to question: String) async throws -> AssistantReply
}

/// The state of the system model as the availability seam reports it (mirrors
/// `SystemLanguageModel.availability` without importing it).
public enum LanguageModelStatus: Sendable, Hashable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unknown
}

/// Seam over `SystemLanguageModel.availability`, so the mapping is testable without the model.
public protocol LanguageModelAvailabilityProviding: Sendable {
    /// The current state of the system model.
    var status: LanguageModelStatus { get }
}

extension AssistantAvailability {
    /// Maps the system model's state to the assistant's availability.
    public init(status: LanguageModelStatus) {
        switch status {
        case .available: self = .available
        case .deviceNotEligible: self = .unavailable(.deviceNotEligible)
        case .appleIntelligenceNotEnabled: self = .unavailable(.appleIntelligenceDisabled)
        case .modelNotReady: self = .unavailable(.modelNotReady)
        case .unknown: self = .unavailable(.unknown)
        }
    }
}
