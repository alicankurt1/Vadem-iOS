import Foundation
import VademCore

#if canImport(FoundationModels)
import FoundationModels

/// ``LanguageModelAvailabilityProviding`` backed by `SystemLanguageModel.default`.
@available(iOS 26, macOS 26, *)
public struct SystemLanguageModelAvailability: LanguageModelAvailabilityProviding {
    /// Creates the provider.
    public init() {}

    public var status: LanguageModelStatus {
        switch SystemLanguageModel.default.availability {
        case .available: .available
        case .unavailable(.deviceNotEligible): .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady): .modelNotReady
        case .unavailable: .unknown
        }
    }
}

/// Maps session errors to friendly failures.
@available(iOS 26, macOS 26, *)
enum AssistantErrorMapper {
    static func kind(of error: any Error) -> AssistantFailureKind {
        if error is CancellationError { return .cancelled }
        if let generation = error as? LanguageModelSession.GenerationError {
            switch generation {
            // Model cevap vermeyi reddetti (refusal) de kullanıcıya aynı dostça mesajı verir.
            case .guardrailViolation, .refusal: return .guardrailViolation
            case .exceededContextWindowSize: return .contextWindowExceeded
            default: return .other
            }
        }
        return .other
    }
}

/// The on-device assistant: a `LanguageModelSession` with fixed instructions and read-only tools.
///
/// Every question gets a fresh session over a fresh snapshot of the data, so answers never go stale.
@available(iOS 26, macOS 26, *)
public struct FoundationModelsAssistantEngine: AssistantEngine {
    private let snapshot: @Sendable () async throws -> AssistantQueries
    private let availabilityProvider: any LanguageModelAvailabilityProviding
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let generate: @Sendable (_ instructions: String, _ prompt: String, _ toolbox: AssistantToolbox) async throws -> String

    /// Creates the engine. `snapshot` loads the current data for each question.
    public init(
        snapshot: @escaping @Sendable () async throws -> AssistantQueries,
        availabilityProvider: any LanguageModelAvailabilityProviding = SystemLanguageModelAvailability(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(
            snapshot: snapshot, availabilityProvider: availabilityProvider,
            calendar: calendar, now: now, generate: Self.generateWithSession
        )
    }

    /// Test seam: `generate` replaces the real session call (instructions, prompt, toolbox → text).
    init(
        snapshot: @escaping @Sendable () async throws -> AssistantQueries,
        availabilityProvider: any LanguageModelAvailabilityProviding = SystemLanguageModelAvailability(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() },
        generate: @escaping @Sendable (_ instructions: String, _ prompt: String, _ toolbox: AssistantToolbox) async throws -> String
    ) {
        self.snapshot = snapshot
        self.availabilityProvider = availabilityProvider
        self.calendar = calendar
        self.now = now
        self.generate = generate
    }

    // Gerçek oturum: her soru için yeni LanguageModelSession ve beş salt okunur araç.
    private static func generateWithSession(instructions: String, prompt: String, toolbox: AssistantToolbox) async throws -> String {
        let session = LanguageModelSession(
            tools: [
                MonthTotalTool(toolbox: toolbox),
                PaymentsInMonthTool(toolbox: toolbox),
                NextPaymentTool(toolbox: toolbox),
                CardTotalTool(toolbox: toolbox),
                DebtFreeMonthTool(toolbox: toolbox),
            ],
            instructions: instructions
        )
        return try await session.respond(to: prompt).content
    }

    public var availability: AssistantAvailability {
        AssistantAvailability(status: availabilityProvider.status)
    }

    public func respond(to question: String) async throws -> AssistantReply {
        guard availability == .available else { return .failure(AssistantFailure(kind: .unavailable)) }
        do {
            let toolbox = AssistantToolbox(queries: try await snapshot(), calendar: calendar, now: now)
            let prompt = AssistantPromptBuilder.prompt(for: question, today: now(), calendar: calendar)
            let text = try await generate(AssistantPromptBuilder.instructions, prompt, toolbox)
            return text.isEmpty ? .failure(AssistantFailure(kind: .other)) : .text(text)
        } catch {
            // Oturum hataları kullanıcıya dostça bir cevap olur; uygulama çökmez.
            return .failure(AssistantFailure(kind: AssistantErrorMapper.kind(of: error)))
        }
    }
}

// MARK: Tools (salt okunur; hepsi AssistantToolbox'a devreder)

@available(iOS 26, macOS 26, *)
struct MonthTotalTool: Tool {
    @Generable
    struct Arguments {
        @Guide(description: "Month as YYYY-MM, for example 2026-03. Empty for the current month.")
        var month: String
    }

    let toolbox: AssistantToolbox
    let name = "monthTotal"
    let description = "Returns the exact total the user has to pay in one month and the number of payments."

    func call(arguments: Arguments) async throws -> String {
        toolbox.monthTotal(month: arguments.month)
    }
}

@available(iOS 26, macOS 26, *)
struct PaymentsInMonthTool: Tool {
    @Generable
    struct Arguments {
        @Guide(description: "Month as YYYY-MM, for example 2026-03. Empty for the current month.")
        var month: String
    }

    let toolbox: AssistantToolbox
    let name = "paymentsInMonth"
    let description = "Lists the payments (installments and subscriptions) due in one month."

    func call(arguments: Arguments) async throws -> String {
        toolbox.payments(month: arguments.month)
    }
}

@available(iOS 26, macOS 26, *)
struct NextPaymentTool: Tool {
    @Generable
    struct Arguments {}

    let toolbox: AssistantToolbox
    let name = "nextPayment"
    let description = "Returns the next upcoming payment and how many days away it is."

    func call(arguments: Arguments) async throws -> String {
        toolbox.nextPayment()
    }
}

@available(iOS 26, macOS 26, *)
struct CardTotalTool: Tool {
    @Generable
    struct Arguments {
        @Guide(description: "The name of the card, as the user calls it.")
        var cardName: String
        @Guide(description: "Month as YYYY-MM, for example 2026-03. Empty for the current month.")
        var month: String
    }

    let toolbox: AssistantToolbox
    let name = "cardTotal"
    let description = "Returns what one credit card is due in a month. Says so when no card has that name."

    func call(arguments: Arguments) async throws -> String {
        toolbox.cardTotal(cardName: arguments.cardName, month: arguments.month)
    }
}

@available(iOS 26, macOS 26, *)
struct DebtFreeMonthTool: Tool {
    @Generable
    struct Arguments {}

    let toolbox: AssistantToolbox
    let name = "debtFreeMonth"
    let description = "Returns the last month with an installment payment, i.e. when the installment debt ends."

    func call(arguments: Arguments) async throws -> String {
        toolbox.debtFreeMonth()
    }
}
#endif

/// Answers every question with "unavailable": used below iOS 26, where there is no on-device model.
public struct UnsupportedOSAssistantEngine: AssistantEngine {
    /// Creates the engine.
    public init() {}

    public var availability: AssistantAvailability { .unsupportedOS }

    public func respond(to question: String) async throws -> AssistantReply {
        .failure(AssistantFailure(kind: .unavailable))
    }
}

/// Picks the engine the running OS can offer.
public enum AssistantEngineFactory {
    /// The Foundation Models engine on iOS 26 / macOS 26, otherwise ``UnsupportedOSAssistantEngine``.
    /// `snapshot` loads the current data for each question.
    public static func makeSystemEngine(
        snapshot: @escaping @Sendable () async throws -> AssistantQueries
    ) -> any AssistantEngine {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            return FoundationModelsAssistantEngine(snapshot: snapshot)
        }
        #endif
        return UnsupportedOSAssistantEngine()
    }
}
