import Testing
import VademCore
import VademTestSupport

// Bellek içi referans uygulama, ortak depo sözleşmesinin tamamından geçer.
struct RepositoryFactory: Sendable, CustomTestStringConvertible {
    let name: String
    let make: @MainActor @Sendable () throws -> any PaymentRepository

    var testDescription: String { name }

    static let all: [RepositoryFactory] = [
        RepositoryFactory(name: "InMemory") { InMemoryPaymentRepository() },
    ]
}

@MainActor
@Suite("PaymentRepository contract")
struct PaymentRepositoryContractTests {
    @Test("Contract scenario", arguments: RepositoryFactory.all, PaymentRepositoryContract.scenarios)
    func contract(factory: RepositoryFactory, scenario: PaymentRepositoryContract.Scenario) throws {
        try scenario.run(factory.make())
    }
}
