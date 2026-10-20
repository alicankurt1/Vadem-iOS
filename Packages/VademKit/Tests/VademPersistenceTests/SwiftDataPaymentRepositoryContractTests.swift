import Testing
import VademCore
import VademPersistence
import VademTestSupport

// SwiftData uygulaması, bellek içi referansla aynı ortak sözleşmenin tamamından geçer.
// Her senaryo kendi taze, bellek içi kabını alır; senaryolar birbirini etkilemez.
struct SwiftDataRepositoryFactory: Sendable, CustomTestStringConvertible {
    let name: String
    let make: @MainActor @Sendable () throws -> any PaymentRepository

    var testDescription: String { name }

    static let all: [SwiftDataRepositoryFactory] = [
        SwiftDataRepositoryFactory(name: "SwiftData (in-memory)") {
            try SwiftDataPaymentRepository(container: VademPersistence.makeContainer(storage: .inMemory))
        },
    ]
}

@MainActor
@Suite("SwiftDataPaymentRepository contract")
struct SwiftDataPaymentRepositoryContractTests {
    @Test("Contract scenario", arguments: SwiftDataRepositoryFactory.all, PaymentRepositoryContract.scenarios)
    func contract(factory: SwiftDataRepositoryFactory, scenario: PaymentRepositoryContract.Scenario) throws {
        try scenario.run(factory.make())
    }
}
