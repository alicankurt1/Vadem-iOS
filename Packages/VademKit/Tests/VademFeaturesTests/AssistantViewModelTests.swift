import Foundation
import Testing
@testable import VademFeatures

/// Cevabı elle serbest bırakılan motor: "devam eden soru" durumunu belirleyici sınamak için.
private final class GatedEngine: AssistantEngine, @unchecked Sendable {
    let availability: AssistantAvailability = .available
    private let lock = NSLock()
    private var continuation: CheckedContinuation<AssistantReply, any Error>?
    private var asked: [String] = []

    var questions: [String] { lock.withLock { asked } }

    func respond(to question: String) async throws -> AssistantReply {
        lock.withLock { asked.append(question) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<AssistantReply, any Error>) in
                lock.withLock { continuation = c }
            }
        } onCancel: {
            // İptalde bekleyen çağrı CancellationError ile biter.
            let c = lock.withLock { () -> CheckedContinuation<AssistantReply, any Error>? in
                defer { continuation = nil }
                return continuation
            }
            c?.resume(throwing: CancellationError())
        }
    }

    func release(_ reply: AssistantReply) {
        let c = lock.withLock { () -> CheckedContinuation<AssistantReply, any Error>? in
            defer { continuation = nil }
            return continuation
        }
        c?.resume(returning: reply)
    }
}

private struct Boom: Error {}

@MainActor
@Suite("Assistant view model")
struct AssistantViewModelTests {
    private func make(
        _ steps: [ScriptedAssistantEngine.Step] = [],
        availability: AssistantAvailability = .available
    ) -> (AssistantViewModel, ScriptedAssistantEngine) {
        let engine = ScriptedAssistantEngine(availability: availability, steps: steps)
        return (AssistantViewModel(engine: engine), engine)
    }

    @Test("Starts with an empty conversation")
    func startsEmpty() {
        let (model, _) = make()
        #expect(model.messages.isEmpty)
        #expect(!model.isResponding)
        #expect(model.input.isEmpty)
    }

    @Test("Send appends the question and the answer, clears the input")
    func sendAppendsBoth() async {
        let (model, engine) = make([.reply(.text("You pay 100."))])
        model.input = "  How much?  "
        await model.send()?.value
        #expect(model.input.isEmpty)
        #expect(model.messages.map(\.role) == [.user, .assistant])
        #expect(model.messages.map(\.text) == ["How much?", "You pay 100."])
        #expect(engine.questions == ["How much?"])
        #expect(!model.isResponding)
    }

    @Test("Message ids increase in order")
    func idsIncrease() async {
        let (model, _) = make([.reply(.text("a")), .reply(.text("b"))])
        model.input = "one"
        await model.send()?.value
        model.input = "two"
        await model.send()?.value
        let ids = model.messages.map(\.id)
        #expect(ids.count == 4)
        #expect(ids == ids.sorted())
        #expect(Set(ids).count == 4)
    }

    @Test("Blank input is ignored", arguments: ["", " ", "   \n\t "])
    func blankIgnored(text: String) {
        let (model, engine) = make()
        model.input = text
        #expect(!model.canSend)
        #expect(model.send() == nil)
        #expect(model.messages.isEmpty)
        #expect(engine.questions.isEmpty)
    }

    @Test("Suggestion tap sends its text and keeps the typed input")
    func suggestionTap() async {
        let (model, engine) = make([.reply(.text("Answer"))])
        model.input = "half typed"
        await model.send(suggestion: AssistantViewModel.suggestions[1])?.value
        #expect(engine.questions == ["What is my next payment?"])
        #expect(model.messages.map(\.text) == ["What is my next payment?", "Answer"])
        #expect(model.input == "half typed")
    }

    @Test("Suggestions are the three product chips in order")
    func suggestionList() {
        #expect(AssistantViewModel.suggestions == [
            "How much do I pay this month?",
            "What is my next payment?",
            "When am I debt-free?",
        ])
    }

    @Test("In flight: responding, cannot send, no double send")
    func inFlight() async {
        let engine = GatedEngine()
        let model = AssistantViewModel(engine: engine)
        model.input = "first"
        let task = model.send()
        #expect(task != nil)
        #expect(model.isResponding)
        model.input = "second"
        #expect(!model.canSend)
        #expect(model.send() == nil)
        #expect(model.send(suggestion: "When am I debt-free?") == nil)
        #expect(model.messages.count == 1)
        // Reddedilen gönderim girdiyi silmez.
        #expect(model.input == "second")

        // Motor soruyu görene dek bekle, sonra bırak.
        while engine.questions.isEmpty { await Task.yield() }
        engine.release(.text("done"))
        await task?.value
        #expect(!model.isResponding)
        #expect(engine.questions == ["first"])
        #expect(model.messages.map(\.text) == ["first", "done"])
        #expect(model.canSend)
    }

    @Test("Failure reply becomes a friendly failure message")
    func failureReply() async {
        let failure = AssistantFailure(kind: .guardrailViolation)
        let (model, _) = make([.reply(.failure(failure))])
        await model.send(suggestion: "Hi")?.value
        let last = model.messages.last
        #expect(last?.role == .assistant)
        #expect(last?.isFailure == true)
        #expect(last?.text == failure.message)
        #expect(!model.isResponding)
    }

    @Test("A thrown error becomes a failure message and unlocks the input")
    func thrownError() async {
        let (model, _) = make([.throwing(Boom()), .reply(.text("ok"))])
        await model.send(suggestion: "Hi")?.value
        #expect(model.messages.last?.isFailure == true)
        #expect(model.messages.last?.text == AssistantFailure(kind: .other).message)
        #expect(!model.isResponding)
        // Hatadan sonra yeniden sorulabilir.
        await model.send(suggestion: "Again")?.value
        #expect(model.messages.last?.text == "ok")
        #expect(model.messages.last?.isFailure == false)
    }

    @Test("Normal answers are not failures")
    func successNotFailure() async {
        let (model, _) = make([.reply(.text("fine"))])
        await model.send(suggestion: "Hi")?.value
        #expect(model.messages.allSatisfy { !$0.isFailure })
    }

    @Test("Cancel drops the answer in flight and re-enables input")
    func cancelDropsAnswer() async {
        let engine = GatedEngine()
        let model = AssistantViewModel(engine: engine)
        let task = model.send(suggestion: "Hi")
        #expect(model.isResponding)
        while engine.questions.isEmpty { await Task.yield() }
        model.cancel()
        #expect(!model.isResponding)
        engine.release(.text("late"))
        await task?.value
        // Geç gelen cevap konuşmaya eklenmez.
        #expect(model.messages.map(\.text) == ["Hi"])
        #expect(!model.isResponding)
    }

    @Test("After cancel a new question works")
    func askAfterCancel() async {
        let (model, _) = make([.reply(.text("again"))])
        model.cancel()
        await model.send(suggestion: "Hi")?.value
        #expect(model.messages.last?.text == "again")
    }

    @Test("A late answer from a cancelled question does not land in a newer one")
    func lateAnswerAfterNewQuestion() async {
        let engine = GatedEngine()
        let model = AssistantViewModel(engine: engine)
        let old = model.send(suggestion: "old")
        while engine.questions.isEmpty { await Task.yield() }
        model.cancel()
        await old?.value
        let new = model.send(suggestion: "new")
        while engine.questions.count < 2 { await Task.yield() }
        engine.release(.text("new answer"))
        await new?.value
        #expect(model.messages.map(\.text) == ["old", "new", "new answer"])
    }

    @Test("Unavailable model: nothing is sent and an explanation is given",
          arguments: [
              AssistantAvailability.unavailable(.appleIntelligenceDisabled),
              .unavailable(.deviceNotEligible),
              .unavailable(.modelNotReady),
              .unsupportedOS,
          ])
    func unavailable(availability: AssistantAvailability) {
        let (model, engine) = make(availability: availability)
        model.input = "Hello"
        #expect(!model.canSend)
        #expect(model.send() == nil)
        #expect(model.send(suggestion: "Hi") == nil)
        #expect(engine.questions.isEmpty)
        #expect(model.messages.isEmpty)
        #expect(model.unavailableMessage?.isEmpty == false)
    }

    @Test("Available model has no unavailable message")
    func availableNoMessage() {
        let (model, _) = make()
        #expect(model.unavailableMessage == nil)
        #expect(AssistantViewModel.unavailableMessage(for: .available) == nil)
    }

    @Test("Each unavailable reason has its own explanation")
    func distinctMessages() throws {
        let reasons: [AssistantAvailability] = [
            .unavailable(.appleIntelligenceDisabled), .unavailable(.deviceNotEligible),
            .unavailable(.modelNotReady), .unsupportedOS,
        ]
        let texts = try reasons.map { try #require(AssistantViewModel.unavailableMessage(for: $0)) }
        #expect(Set(texts).count == reasons.count)
        #expect(texts[0].contains("Apple Intelligence"))
        #expect(texts[1].lowercased().contains("device"))
        #expect(texts[2].lowercased().contains("download"))
    }

    @Test("VoiceOver label names the speaker")
    func accessibilityLabels() async {
        let (model, _) = make([.reply(.text("Answer"))])
        await model.send(suggestion: "Question")?.value
        #expect(model.messages.map(\.accessibilityLabel) == ["You: Question", "Assistant: Answer"])
    }

    @Test("Footer and read-only notes are present")
    func notes() {
        #expect(AssistantViewModel.footerNote.contains("on this device"))
        #expect(AssistantViewModel.footerNote.contains("wrong"))
        #expect(AssistantViewModel.readOnlyNote.contains("read"))
    }
}

/// Kullanılabilirliği sonradan değişen motor (model indirmesi bitince): yenileme testi için.
private final class MutableAvailabilityEngine: AssistantEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var current: AssistantAvailability

    init(_ availability: AssistantAvailability) { current = availability }

    var availability: AssistantAvailability {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    func respond(to question: String) async throws -> AssistantReply { .text("OK") }
}

@MainActor
@Suite("Assistant view model availability refresh")
struct AssistantAvailabilityRefreshTests {
    @Test("Refresh picks up modelNotReady to available")
    func modelBecomesReady() {
        let engine = MutableAvailabilityEngine(.unavailable(.modelNotReady))
        let model = AssistantViewModel(engine: engine)
        #expect(model.availability == .unavailable(.modelNotReady))

        engine.availability = .available
        // Yenilemeden önce eski değer korunur.
        #expect(model.availability == .unavailable(.modelNotReady))
        model.refreshAvailability()
        #expect(model.availability == .available)
    }

    @Test("Refresh picks up available to unavailable")
    func modelBecomesUnavailable() {
        let engine = MutableAvailabilityEngine(.available)
        let model = AssistantViewModel(engine: engine)
        engine.availability = .unavailable(.appleIntelligenceDisabled)
        model.refreshAvailability()
        #expect(model.availability == .unavailable(.appleIntelligenceDisabled))
    }

    @Test("Refresh without a change keeps the value")
    func unchanged() {
        let model = AssistantViewModel(engine: MutableAvailabilityEngine(.unsupportedOS))
        model.refreshAvailability()
        #expect(model.availability == .unsupportedOS)
    }
}
