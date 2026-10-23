import Foundation
import VademFeatures
import VademPersistence

/// Opens the App Group store and asks ``PaymentSummaryProvider`` for an answer; shared by the intents.
@MainActor
enum IntentAnswers {
    /// The answer `ask` gives for the saved payments, or ``PaymentSummaryProvider/failureAnswer``
    /// when the store cannot be opened.
    static func answer(_ ask: (PaymentSummaryProvider) -> String) -> String {
        do {
            let container = try VademPersistence.makeContainer(storage: .appGroup)
            let provider = PaymentSummaryProvider(repository: SwiftDataPaymentRepository(container: container))
            return ask(provider)
        } catch {
            // Depo açılamazsa Siri yine sabit bir cümleyle cevap verir.
            return PaymentSummaryProvider.failureAnswer
        }
    }
}
