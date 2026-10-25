import Foundation
import Testing
import VademCore
import VademFeatures

@MainActor
@Suite("HomeViewModel assistant entry")
struct HomeAssistantEntryTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
    }

    private static func home(engine: ScriptedAssistantEngine) -> HomeViewModel {
        HomeViewModel(
            repository: InMemoryPaymentRepository(), today: today, calendar: calendar, assistant: engine
        )
    }

    // Giriş kuralı: sadece desteklenmeyen OS'te gizlenir; kullanılamayan model açıklamasını gösterir.
    @Test(
        "Shows the assistant unless the OS is unsupported",
        arguments: [
            (AssistantAvailability.available, true),
            (.unavailable(.deviceNotEligible), true),
            (.unavailable(.appleIntelligenceDisabled), true),
            (.unavailable(.modelNotReady), true),
            (.unavailable(.unknown), true),
            (.unsupportedOS, false),
        ]
    )
    func showsAssistant(availability: AssistantAvailability, expected: Bool) {
        let home = Self.home(engine: ScriptedAssistantEngine(availability: availability))
        #expect(home.showsAssistant == expected)
    }

    @Test(
        "makeAssistantModel starts empty and carries the engine availability",
        arguments: [
            AssistantAvailability.available,
            .unavailable(.appleIntelligenceDisabled),
            .unsupportedOS,
        ]
    )
    func modelAvailability(availability: AssistantAvailability) {
        let home = Self.home(engine: ScriptedAssistantEngine(availability: availability))
        let model = home.makeAssistantModel()
        #expect(model.availability == availability)
        #expect(model.messages.isEmpty)
    }

    @Test("makeAssistantModel answers through the injected engine")
    func usesInjectedEngine() async throws {
        let engine = ScriptedAssistantEngine(steps: [.reply(.text("Injected answer"))])
        let model = Self.home(engine: engine).makeAssistantModel()

        model.input = "How much do I pay this month?"
        let task = try #require(model.send())
        await task.value

        #expect(engine.questions == ["How much do I pay this month?"])
        #expect(model.messages.last?.text == "Injected answer")
    }

    @Test("Every makeAssistantModel call returns a fresh conversation")
    func freshConversations() async throws {
        let engine = ScriptedAssistantEngine()
        let home = Self.home(engine: engine)
        let first = home.makeAssistantModel()
        first.input = "Hello"
        await first.send()?.value
        #expect(!first.messages.isEmpty)
        #expect(home.makeAssistantModel().messages.isEmpty)
    }
}
