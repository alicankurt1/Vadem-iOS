import Foundation
import Observation

/// Drives the assistant chat: the conversation, the input and the one question in flight.
///
/// Read-only by design: it only asks the ``AssistantEngine``; nothing is saved, so a new model
/// (a new screen) starts with an empty conversation. Call ``cancel()`` when the screen closes.
@MainActor
@Observable
public final class AssistantViewModel {
    /// One message of the conversation.
    public struct Message: Sendable, Hashable, Identifiable {
        /// Who wrote the message.
        public enum Role: Sendable, Hashable {
            /// The user's question.
            case user
            /// The assistant's answer (or a friendly failure).
            case assistant
        }

        /// Unique within the conversation, increasing in order.
        public let id: Int
        /// Who wrote it.
        public let role: Role
        /// The text shown in the bubble.
        public let text: String
        /// `true` when the assistant could not answer (``text`` is the failure message).
        public let isFailure: Bool

        /// The message as one VoiceOver label: `"You: …"` or `"Assistant: …"`.
        public var accessibilityLabel: String {
            role == .user
                ? String(localized: "You: \(text)", bundle: .module, comment: "Spoken user message")
                : String(localized: "Assistant: \(text)", bundle: .module, comment: "Spoken assistant message")
        }
    }

    /// The suggestion chips, in display order.
    public nonisolated static var suggestions: [String] {
        [
            String(localized: "How much do I pay this month?", bundle: .module),
            String(localized: "What is my next payment?", bundle: .module),
            String(localized: "When am I debt-free?", bundle: .module),
        ]
    }

    /// The footer note under the input.
    public nonisolated static var footerNote: String {
        String(localized: "Answers come from your data on this device and can be wrong.", bundle: .module)
    }

    /// The empty state's text: the assistant only reads.
    public nonisolated static var readOnlyNote: String {
        String(
            localized: "Ask about your payments. The assistant can only read your data; it can't add, edit or delete anything.",
            bundle: .module
        )
    }

    /// The text being typed.
    public var input = ""
    /// The conversation, oldest first.
    public private(set) var messages: [Message] = []
    /// `true` while a question waits for its answer; the input is disabled meanwhile.
    public private(set) var isResponding = false
    /// Whether the engine can answer; read when the model is made and on ``refreshAvailability()``.
    public private(set) var availability: AssistantAvailability

    @ObservationIgnored private let engine: any AssistantEngine
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var nextID = 0
    // Her soru yeni bir numara alır; iptal edilmiş eski cevap bu numarayla ayıklanır.
    @ObservationIgnored private var requestID = 0

    /// Creates a model with an empty conversation on `engine`.
    public init(engine: any AssistantEngine) {
        self.engine = engine
        self.availability = engine.availability
    }

    /// `true` when ``send()`` would send: the assistant is available, nothing is in flight and the
    /// input has text other than whitespace.
    public var canSend: Bool {
        availability == .available && !isResponding && !Self.trimmed(input).isEmpty
    }

    /// The explanation shown instead of the chat, or `nil` when the assistant is available.
    public var unavailableMessage: String? {
        Self.unavailableMessage(for: availability)
    }

    /// The explanation for `availability`, or `nil` for ``AssistantAvailability/available``.
    public nonisolated static func unavailableMessage(for availability: AssistantAvailability) -> String? {
        switch availability {
        case .available:
            return nil
        case .unavailable(.appleIntelligenceDisabled):
            return String(
                localized: "Apple Intelligence is turned off. Turn it on in Settings to use the assistant.", bundle: .module
            )
        case .unavailable(.deviceNotEligible):
            return String(
                localized: "This device doesn't support Apple Intelligence, so the assistant can't run here.", bundle: .module
            )
        case .unavailable(.modelNotReady):
            return String(
                localized: "The on-device model is still downloading. Try again in a little while.", bundle: .module
            )
        case .unavailable(.unknown):
            return String(localized: "The assistant is not available right now. Try again later.", bundle: .module)
        case .unsupportedOS:
            return String(localized: "The assistant needs iOS 26 or later.", bundle: .module)
        }
    }

    /// Reads the engine's availability again (e.g. when the screen appears after the model downloaded).
    public func refreshAvailability() {
        availability = engine.availability
    }

    /// Sends ``input`` and clears it. Ignored while a question is in flight or when ``input`` is blank.
    ///
    /// Returns the task that waits for the answer (tests can await its `value`), or `nil` when ignored.
    @discardableResult
    public func send() -> Task<Void, Never>? {
        let task = ask(input)
        if task != nil { input = "" }
        return task
    }

    /// Sends a suggestion chip's text; ignored while a question is in flight. ``input`` is kept.
    @discardableResult
    public func send(suggestion: String) -> Task<Void, Never>? {
        ask(suggestion)
    }

    /// Cancels the question in flight (call it when the screen closes); its answer is dropped.
    public func cancel() {
        task?.cancel()
        task = nil
        // Eski isteğin cevabı artık hiçbir şeyi değiştirmez.
        requestID += 1
        isResponding = false
    }

    private func ask(_ text: String) -> Task<Void, Never>? {
        let question = Self.trimmed(text)
        // Boş soru ve ikinci gönderim yok sayılır; uygun değilken de gönderilmez.
        guard availability == .available, !isResponding, !question.isEmpty else { return nil }
        append(.user, question, isFailure: false)
        isResponding = true
        requestID += 1
        let id = requestID
        let engine = engine
        let task = Task { [weak self] in
            let reply: AssistantReply
            do {
                reply = try await engine.respond(to: question)
            } catch {
                // Beklenmeyen hata da dostça bir mesaja dönüşür.
                reply = .failure(AssistantFailure(kind: error is CancellationError ? .cancelled : .other))
            }
            self?.finish(id: id, reply: reply)
        }
        self.task = task
        return task
    }

    private func finish(id: Int, reply: AssistantReply) {
        // İptal edilmiş (ekran kapanmış) isteğin cevabı gösterilmez.
        guard id == requestID, isResponding else { return }
        switch reply {
        case .text(let text):
            append(.assistant, text, isFailure: false)
        case .failure(let failure):
            append(.assistant, failure.message, isFailure: true)
        }
        isResponding = false
        task = nil
    }

    private func append(_ role: Message.Role, _ text: String, isFailure: Bool) {
        messages.append(Message(id: nextID, role: role, text: text, isFailure: isFailure))
        nextID += 1
    }

    private nonisolated static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
