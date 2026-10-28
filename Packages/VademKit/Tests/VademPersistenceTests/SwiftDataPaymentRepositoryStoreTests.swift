import Foundation
import SwiftData
import Testing
import VademCore
@testable import VademPersistence
import VademTestSupport

// Testler için geçici bir dizinde dosya deposu; test bitince dizin silinir
// (SQLite'ın -wal / -shm dosyaları da dahil).
enum TemporaryStore {
    static func with(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VademPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("Vadem.store"))
    }
}

// Round-trip'in hangi yoldan geçtiği: aynı bellek içi kap ya da diske yazılıp yeni kapla açılan dosya.
// Yeniden açma, değerlerin bellekteki nesnelerden değil depodan okunduğunu kanıtlar.
enum StorageKind: String, Sendable, CaseIterable, CustomTestStringConvertible {
    case inMemory
    case file

    var testDescription: String { rawValue }

    func storage(_ url: URL) -> VademPersistence.Storage {
        switch self {
        case .inMemory: .inMemory
        case .file: .file(url)
        }
    }
}

@MainActor
enum RoundTrip {
    // `write` ile kaydeder, sonra (dosya deposunda yeni bir kapla) `read` ile okur.
    static func run<T>(
        _ kind: StorageKind,
        write: (SwiftDataPaymentRepository) throws -> Void,
        read: (SwiftDataPaymentRepository) throws -> T
    ) throws -> T {
        var result: T?
        try TemporaryStore.with { url in
            switch kind {
            case .inMemory:
                let repository = try SwiftDataPaymentRepository(container: VademPersistence.makeContainer(storage: .inMemory))
                try write(repository)
                result = try read(repository)
            case .file:
                // İlk kap bu blokta kalır; okuma tamamen yeni bir kapla yapılır.
                do {
                    let repository = try SwiftDataPaymentRepository(container: VademPersistence.makeContainer(storage: .file(url)))
                    try write(repository)
                }
                let reopened = try SwiftDataPaymentRepository(container: VademPersistence.makeContainer(storage: .file(url)))
                result = try read(reopened)
            }
        }
        return try #require(result)
    }
}

private func decimal(_ text: String) throws -> Decimal {
    try #require(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")))
}

@MainActor
@Suite("SwiftDataPaymentRepository store")
struct SwiftDataPaymentRepositoryStoreTests {
    // MARK: - Yeniden açma

    @Test("Data survives reopening a file store, in the contract's order")
    func survivesReopening() throws {
        // Beklenen sıra elle: kartlar ada göre (büyük/küçük harf duyarsız), taksitler ilk aya
        // sonra başlığa göre, abonelikler başlığa göre. Kayıt sırası bilerek ters.
        let bonus = try Fixture.card("bonus", id: Fixture.id(1))
        let axess = try Fixture.card("Axess", id: Fixture.id(2))
        let phone = try Fixture.installment(
            "Telefon", id: Fixture.id(3), card: bonus.id,
            plan: Fixture.plan(total: 1200, count: 3, first: Fixture.month(2026, 3))
        )
        let laptop = try Fixture.installment(
            "Laptop", id: Fixture.id(4), card: axess.id,
            plan: Fixture.plan(total: 30000, count: 12, first: Fixture.month(2026, 1))
        )
        let music = try Fixture.subscriptionItem("Müzik", id: Fixture.id(5), card: bonus.id)
        let film = try Fixture.subscriptionItem("film", id: Fixture.id(6), card: nil)

        try TemporaryStore.with { url in
            do {
                let repository = try SwiftDataPaymentRepository(container: VademPersistence.makeContainer(storage: .file(url)))
                try repository.save(bonus)
                try repository.save(axess)
                try repository.save(phone)
                try repository.save(laptop)
                try repository.save(music)
                try repository.save(film)
            }

            let reopened = try SwiftDataPaymentRepository(container: VademPersistence.makeContainer(storage: .file(url)))
            #expect(try reopened.cards() == [axess, bonus])
            #expect(try reopened.installments() == [laptop, phone])
            #expect(try reopened.subscriptions() == [film, music])
        }
    }

    @Test("Updates and deletes survive reopening a file store")
    func updatesAndDeletesSurviveReopening() throws {
        let card = try Fixture.card("Bonus", id: Fixture.id(1))
        let renamed = try #require(Card(id: card.id, name: "Bonus Platinum", statementDay: 1, dueDay: 31))
        let kept = try Fixture.installment("Telefon", id: Fixture.id(2), card: card.id)
        let removed = try Fixture.installment("Laptop", id: Fixture.id(3), card: card.id)
        let subscription = try Fixture.subscriptionItem("Müzik", id: Fixture.id(4), card: card.id)
        let detached = try Fixture.subscriptionItem("Müzik", id: subscription.id, card: nil)

        try TemporaryStore.with { url in
            do {
                let repository = try SwiftDataPaymentRepository(container: VademPersistence.makeContainer(storage: .file(url)))
                try repository.save(card)
                try repository.save(kept)
                try repository.save(removed)
                try repository.save(subscription)
                try repository.save(renamed)
                try repository.deleteInstallment(id: removed.id)
                try repository.save(detached)
            }

            let reopened = try SwiftDataPaymentRepository(container: VademPersistence.makeContainer(storage: .file(url)))
            #expect(try reopened.cards() == [renamed])
            #expect(try reopened.installments() == [kept])
            #expect(try reopened.subscriptions() == [detached])
        }
    }

    @Test("An empty file store reopens empty")
    func emptyStoreReopensEmpty() throws {
        try TemporaryStore.with { url in
            do { _ = try VademPersistence.makeContainer(storage: .file(url)) }
            let reopened = try SwiftDataPaymentRepository(container: VademPersistence.makeContainer(storage: .file(url)))
            #expect(try reopened.cards().isEmpty)
            #expect(try reopened.installments().isEmpty)
            #expect(try reopened.subscriptions().isEmpty)
        }
    }

    // MARK: - Para birebir

    // Double'a çevrilse bozulacak değerler; metin olarak verilir ki Double literali araya girmesin.
    nonisolated static let amounts = ["0.01", "0.10", "0.99", "1.01", "333.34", "1234567.89", "99999999999.99", "12345678901234.56"]

    @Test("Installment total round-trips exactly", arguments: StorageKind.allCases, amounts)
    func installmentTotalRoundTrips(kind: StorageKind, text: String) throws {
        let expected = try decimal(text)
        let card = try Fixture.card()
        let item = try Fixture.installment(card: card.id, plan: Fixture.plan(total: expected, count: 1))

        let loaded = try RoundTrip.run(kind) { repository in
            try repository.save(card)
            try repository.save(item)
        } read: { try $0.installments() }

        let total = try #require(loaded.first?.plan.total)
        #expect(loaded == [item])
        #expect(total.amount == expected)
        #expect(total.amount.description == expected.description)
    }

    @Test("Subscription amount round-trips exactly", arguments: StorageKind.allCases, amounts)
    func subscriptionAmountRoundTrips(kind: StorageKind, text: String) throws {
        let expected = try decimal(text)
        let item = try Fixture.subscriptionItem(card: nil, subscription: Fixture.subscription(amount: expected))

        let loaded = try RoundTrip.run(kind) { try $0.save(item) } read: { try $0.subscriptions() }

        let amount = try #require(loaded.first?.subscription.amount)
        #expect(loaded == [item])
        #expect(amount.amount == expected)
        #expect(amount.amount.description == expected.description)
    }

    @Test("Installment payments still add up to the total after a round-trip", arguments: StorageKind.allCases)
    func paymentsStillAddUp(kind: StorageKind) throws {
        // 1000 / 3 = 333.33; artan 1 kuruş ilk taksite: 333.34, 333.33, 333.33.
        let card = try Fixture.card()
        let item = try Fixture.installment(card: card.id, plan: Fixture.plan(total: decimal("1000"), count: 3))

        let loaded = try RoundTrip.run(kind) { repository in
            try repository.save(card)
            try repository.save(item)
        } read: { try $0.installments() }

        let plan = try #require(loaded.first?.plan)
        #expect(plan.payments.map(\.amount.amount) == [try decimal("333.34"), try decimal("333.33"), try decimal("333.33")])
    }

    // MARK: - Ay ve günler birebir

    nonisolated static let months: [(Int, Int)] = [(1, 1), (2024, 2), (2026, 12), (9999, 12)]

    @Test("Installment first month round-trips exactly", arguments: StorageKind.allCases, months)
    func installmentMonthRoundTrips(kind: StorageKind, month: (Int, Int)) throws {
        let first = try Fixture.month(month.0, month.1)
        let card = try Fixture.card()
        // Tek taksit: son ay ilk aya eşit, 9999-12 de geçerli kalır.
        let item = try Fixture.installment(card: card.id, plan: Fixture.plan(total: 500, count: 1, first: first))

        let loaded = try RoundTrip.run(kind) { repository in
            try repository.save(card)
            try repository.save(item)
        } read: { try $0.installments() }

        #expect(loaded == [item])
        #expect(loaded.first?.plan.firstMonth.year == month.0)
        #expect(loaded.first?.plan.firstMonth.month == month.1)
    }

    @Test("Installment count round-trips exactly", arguments: StorageKind.allCases, [1, 2, 12, 36])
    func installmentCountRoundTrips(kind: StorageKind, count: Int) throws {
        let card = try Fixture.card()
        let item = try Fixture.installment(card: card.id, plan: Fixture.plan(total: 3600, count: count))

        let loaded = try RoundTrip.run(kind) { repository in
            try repository.save(card)
            try repository.save(item)
        } read: { try $0.installments() }

        #expect(loaded == [item])
        #expect(loaded.first?.plan.count == count)
    }

    nonisolated static let cardDays: [(Int, Int)] = [(1, 1), (1, 31), (31, 1), (10, 20), (28, 5), (31, 31)]

    @Test("Card statement and due days round-trip exactly", arguments: StorageKind.allCases, cardDays)
    func cardDaysRoundTrip(kind: StorageKind, days: (Int, Int)) throws {
        let card = try #require(Card(id: Fixture.id(1), name: "Bonus", statementDay: days.0, dueDay: days.1))

        let loaded = try RoundTrip.run(kind) { try $0.save(card) } read: { try $0.cards() }

        #expect(loaded == [card])
        #expect(loaded.first?.statementDay == days.0)
        #expect(loaded.first?.dueDay == days.1)
    }

    @Test("Card name round-trips exactly, including non-ASCII text", arguments: StorageKind.allCases)
    func cardNameRoundTrips(kind: StorageKind) throws {
        let card = try Fixture.card("Şeker Kart İğüçö", id: Fixture.id(1))

        let loaded = try RoundTrip.run(kind) { try $0.save(card) } read: { try $0.cards() }

        #expect(loaded.first?.name == "Şeker Kart İğüçö")
    }

    // MARK: - Abonelik alanları birebir

    struct SubscriptionCase: Sendable, CustomTestStringConvertible {
        let name: String
        let period: Subscription.Period
        let renewalDay: Int
        let first: (Int, Int)
        let last: (Int, Int)?

        var testDescription: String { name }
    }

    nonisolated static let subscriptionCases: [SubscriptionCase] = [
        SubscriptionCase(name: "monthly, active", period: .monthly, renewalDay: 5, first: (2026, 1), last: nil),
        SubscriptionCase(name: "monthly, day 31, cancelled", period: .monthly, renewalDay: 31, first: (2026, 1), last: (2026, 6)),
        SubscriptionCase(name: "yearly, day 1, active", period: .yearly, renewalDay: 1, first: (2024, 2), last: nil),
        SubscriptionCase(name: "yearly, last month = first month", period: .yearly, renewalDay: 29, first: (2024, 2), last: (2024, 2)),
        SubscriptionCase(name: "monthly, last month far ahead", period: .monthly, renewalDay: 15, first: (1, 1), last: (9999, 12)),
    ]

    @Test("Subscription period, renewal day and optional last month round-trip exactly",
          arguments: StorageKind.allCases, subscriptionCases)
    func subscriptionFieldsRoundTrip(kind: StorageKind, value: SubscriptionCase) throws {
        let first = try Fixture.month(value.first.0, value.first.1)
        let last = try value.last.map { try Fixture.month($0.0, $0.1) }
        let subscription = try #require(Subscription(
            amount: Money(decimal("49.90")), period: value.period, renewalDay: value.renewalDay,
            firstMonth: first, lastMonth: last
        ))
        let item = try Fixture.subscriptionItem(card: nil, subscription: subscription)

        let loaded = try RoundTrip.run(kind) { try $0.save(item) } read: { try $0.subscriptions() }

        let stored = try #require(loaded.first?.subscription)
        #expect(loaded == [item])
        #expect(stored.period == value.period)
        #expect(stored.renewalDay == value.renewalDay)
        #expect(stored.firstMonth == first)
        #expect(stored.lastMonth == last)
    }

    @Test("Subscription cardID round-trips as set or nil", arguments: StorageKind.allCases, [true, false])
    func subscriptionCardIDRoundTrips(kind: StorageKind, hasCard: Bool) throws {
        let card = try Fixture.card(id: Fixture.id(1))
        let item = try Fixture.subscriptionItem(card: hasCard ? card.id : nil)

        let loaded = try RoundTrip.run(kind) { repository in
            try repository.save(card)
            try repository.save(item)
        } read: { try $0.subscriptions() }

        #expect(loaded == [item])
        #expect(loaded.first?.cardID == (hasCard ? card.id : nil))
    }

    @Test("Installment cardID and item ids round-trip exactly", arguments: StorageKind.allCases)
    func installmentIDsRoundTrip(kind: StorageKind) throws {
        let card = try Fixture.card(id: Fixture.id(7))
        let item = try Fixture.installment(id: Fixture.id(8), card: card.id)

        let loaded = try RoundTrip.run(kind) { repository in
            try repository.save(card)
            try repository.save(item)
        } read: { try $0.installments() }

        #expect(loaded.first?.id == Fixture.id(8))
        #expect(loaded.first?.cardID == Fixture.id(7))
    }

    // MARK: - Bozuk kayıt çökmez, hata fırlatır

    // Depoya repository'yi atlayarak kural dışı bir kayıt yazar (ör. eski / bozuk veri).
    private func repository(withStored record: some PersistentModel) throws -> SwiftDataPaymentRepository {
        let container = try VademPersistence.makeContainer(storage: .inMemory)
        let context = ModelContext(container)
        context.insert(record)
        try context.save()
        return SwiftDataPaymentRepository(container: container)
    }

    // Hata türü ve kayıt kimliği doğru mu; `entity` adı uygulamaya bırakılır.
    private func expectInvalidRecord(id: UUID, _ load: () throws -> Void) {
        let error = #expect(throws: PersistenceError.self) { try load() }
        guard case .invalidRecord(_, let recordID)? = error else { return }
        #expect(recordID == id)
    }

    @Test("A stored card with an empty name throws instead of crashing")
    func invalidCardThrows() throws {
        let id = Fixture.id(1)
        let repository = try repository(withStored: VademSchemaV3.CardRecord(id: id, name: "", statementDay: 10, dueDay: 20))
        expectInvalidRecord(id: id) { _ = try repository.cards() }
    }

    @Test("A stored card with day 0 throws instead of crashing")
    func invalidCardDayThrows() throws {
        let id = Fixture.id(1)
        let repository = try repository(withStored: VademSchemaV3.CardRecord(id: id, name: "Bonus", statementDay: 0, dueDay: 20))
        expectInvalidRecord(id: id) { _ = try repository.cards() }
    }

    @Test("A stored installment with unreadable money throws", arguments: ["", "abc", "12abc", "NaN", "0", "-10"])
    func invalidInstallmentTotalThrows(total: String) throws {
        let id = Fixture.id(2)
        let repository = try repository(withStored: VademSchemaV3.InstallmentRecord(
            id: id, title: "Telefon", cardID: Fixture.id(1), paymentDay: nil, total: total, count: 3, firstYear: 2026, firstMonth: 1
        ))
        expectInvalidRecord(id: id) { _ = try repository.installments() }
    }

    @Test("A stored one-time payment with invalid values throws", arguments: [
        ("", 2026, 6, 15), ("0", 2026, 6, 15), ("-5", 2026, 6, 15), ("abc", 2026, 6, 15),
        ("10", 2026, 13, 15), ("10", 2026, 6, 31), ("10", 2026, 6, 0), ("10", 2026, 2, 30),
    ])
    func invalidOneTimePaymentThrows(amount: String, year: Int, month: Int, day: Int) throws {
        let id = Fixture.id(3)
        let repository = try repository(withStored: VademSchemaV3.OneTimePaymentRecord(
            id: id, title: "Vergi", cardID: nil, amount: amount, dueYear: year, dueMonth: month, dueDay: day
        ))
        expectInvalidRecord(id: id) { _ = try repository.oneTimePayments() }
    }

    @Test("A stored installment with an invalid month throws")
    func invalidInstallmentMonthThrows() throws {
        let id = Fixture.id(2)
        let repository = try repository(withStored: VademSchemaV3.InstallmentRecord(
            id: id, title: "Telefon", cardID: Fixture.id(1), paymentDay: nil, total: "1200", count: 3, firstYear: 2026, firstMonth: 13
        ))
        expectInvalidRecord(id: id) { _ = try repository.installments() }
    }

    // Kart ve ödeme günü birlikte (ya da ikisi de yok) olamaz; gün 1...31 dışında olamaz.
    @Test("A stored installment with an invalid card and payment day pair throws", arguments: [
        (UUID?.some(Fixture.id(1)), Int?.some(10)),
        (nil, nil),
        (nil, 0),
        (nil, 32),
    ])
    func invalidInstallmentCardDayPairThrows(cardID: UUID?, paymentDay: Int?) throws {
        let id = Fixture.id(2)
        let repository = try repository(withStored: VademSchemaV3.InstallmentRecord(
            id: id, title: "Telefon", cardID: cardID, paymentDay: paymentDay, total: "1200", count: 3,
            firstYear: 2026, firstMonth: 1
        ))
        expectInvalidRecord(id: id) { _ = try repository.installments() }
    }

    // Geçerli bir abonelik kaydından tek bir alanı bozan durumlar.
    struct SubscriptionRecordCase: Sendable, CustomTestStringConvertible {
        let name: String
        var title = "Müzik"
        var amount = "99"
        var period = "monthly"
        var renewalDay = 5
        var firstYear = 2026
        var firstMonth = 1
        var lastYear: Int?
        var lastMonth: Int?

        var testDescription: String { name }

        func record(id: UUID) -> VademSchemaV3.SubscriptionRecord {
            VademSchemaV3.SubscriptionRecord(
                id: id, title: title, cardID: nil, amount: amount, period: period, renewalDay: renewalDay,
                firstYear: firstYear, firstMonth: firstMonth, lastYear: lastYear, lastMonth: lastMonth
            )
        }
    }

    nonisolated static let corruptSubscriptions: [SubscriptionRecordCase] = [
        SubscriptionRecordCase(name: "unknown period", period: "weekly"),
        SubscriptionRecordCase(name: "empty period", period: ""),
        SubscriptionRecordCase(name: "last year without last month", lastYear: 2026, lastMonth: nil),
        SubscriptionRecordCase(name: "last month without last year", lastYear: nil, lastMonth: 6),
        SubscriptionRecordCase(name: "last month 13", lastYear: 2026, lastMonth: 13),
        SubscriptionRecordCase(name: "last month 0", lastYear: 2026, lastMonth: 0),
        SubscriptionRecordCase(name: "last month before first month", lastYear: 2025, lastMonth: 12),
        SubscriptionRecordCase(name: "unreadable amount", amount: "12abc"),
        SubscriptionRecordCase(name: "empty amount", amount: ""),
        SubscriptionRecordCase(name: "zero amount", amount: "0"),
        SubscriptionRecordCase(name: "first month 13", firstMonth: 13),
        SubscriptionRecordCase(name: "renewal day 32", renewalDay: 32),
        SubscriptionRecordCase(name: "empty title", title: "  "),
    ]

    @Test("A corrupt stored subscription throws instead of crashing", arguments: corruptSubscriptions)
    func invalidSubscriptionThrows(value: SubscriptionRecordCase) throws {
        let id = Fixture.id(3)
        let repository = try repository(withStored: value.record(id: id))
        expectInvalidRecord(id: id) { _ = try repository.subscriptions() }
    }

    // Kontrol: bozulmamış temel kayıt sorunsuz okunur; yani hatayı yalnızca bozulan alan doğurur.
    @Test("An intact stored subscription record reads back", arguments: [
        SubscriptionRecordCase(name: "active"),
        SubscriptionRecordCase(name: "cancelled", lastYear: 2026, lastMonth: 6),
    ])
    func intactSubscriptionReads(value: SubscriptionRecordCase) throws {
        let repository = try repository(withStored: value.record(id: Fixture.id(3)))
        let loaded = try repository.subscriptions()
        #expect(loaded.map(\.id) == [Fixture.id(3)])
        #expect(loaded.first?.subscription.lastMonth == value.lastYear.flatMap { YearMonth(year: $0, month: value.lastMonth ?? 0) })
    }
}
