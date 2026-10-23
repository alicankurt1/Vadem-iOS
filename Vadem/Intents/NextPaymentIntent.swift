import AppIntents
import VademFeatures

/// "What is my next payment?": speaks the nearest upcoming payment without opening the app.
struct NextPaymentIntent: AppIntent {
    static let title: LocalizedStringResource = "Next payment"
    static let description = IntentDescription("Tells your next upcoming payment.")
    // Uygulama açılmadan Siri cevabı söyler.
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = IntentAnswers.answer { $0.nextPaymentAnswer() }
        return .result(dialog: IntentDialog(stringLiteral: answer))
    }
}
