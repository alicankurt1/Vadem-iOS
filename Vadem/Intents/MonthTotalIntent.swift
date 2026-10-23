import AppIntents
import VademFeatures

/// "How much do I pay this month?": speaks the month total without opening the app.
struct MonthTotalIntent: AppIntent {
    static let title: LocalizedStringResource = "Monthly total"
    static let description = IntentDescription("Tells how much you pay this month.")
    // Uygulama açılmadan Siri cevabı söyler.
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = IntentAnswers.answer { $0.monthTotalAnswer() }
        return .result(dialog: IntentDialog(stringLiteral: answer))
    }
}
