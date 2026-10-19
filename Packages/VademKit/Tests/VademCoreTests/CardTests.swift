import Foundation
import Testing
import VademCore

// Test verisi için kısa yardımcı: geçersiz ay testin kendisinde bir hatadır.
private func ym(_ year: Int, _ month: Int) -> YearMonth {
    guard let value = YearMonth(year: year, month: month) else {
        fatalError("Invalid test month: \(year)-\(month)")
    }
    return value
}

// Geçerli olması beklenen kart; nil dönerse test kurulumu hatalıdır.
private func card(
    _ name: String = "Bonus",
    statement: Int,
    due: Int,
    id: UUID = UUID()
) throws -> Card {
    try #require(Card(id: id, name: name, statementDay: statement, dueDay: due))
}

// Derleme zamanı konformans kontrolü: Card bu kısıtları sağlamazsa derlenmez.
private func requiresConformances<T: Sendable & Hashable & Codable & Identifiable>(_: T.Type) -> Bool
where T.ID == UUID {
    true
}

// Codable'ı JSON nesnesi içinde test etmek için sarmalayıcı.
private struct Box: Codable, Equatable {
    let card: Card
}

private let fixedID = UUID(uuidString: "6F1C2A3B-4D5E-4F60-8172-93A4B5C6D7E8")!

// Elle yazılmış JSON; alan adları özellik adlarıyla aynı kabul edilir.
private func json(id: String = fixedID.uuidString, name: String, statementDay: Int, dueDay: Int) -> Data {
    let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")
    return Data("""
    {"card": {"id": "\(id)", "name": "\(escapedName)", "statementDay": \(statementDay), "dueDay": \(dueDay)}}
    """.utf8)
}

@Suite("Card")
struct CardTests {

    // MARK: - Tip ve saklama

    @Test("Conforms to Sendable, Hashable, Codable and Identifiable with a UUID id")
    func conformances() {
        #expect(requiresConformances(Card.self))
    }

    @Test("Keeps id, name, statement day and due day")
    func storesProperties() throws {
        let c = try card("Maximum", statement: 31, due: 10, id: fixedID)
        #expect(c.id == fixedID)
        #expect(c.name == "Maximum")
        #expect(c.statementDay == 31)
        #expect(c.dueDay == 10)
    }

    @Test("Defaults id to a new UUID for each card")
    func defaultIDIsUnique() throws {
        let a = try #require(Card(name: "Bonus", statementDay: 1, dueDay: 10))
        let b = try #require(Card(name: "Bonus", statementDay: 1, dueDay: 10))
        #expect(a.id != b.id)
        #expect(a != b)
    }

    // MARK: - İsim doğrulama

    @Test(
        "Trims whitespace and newlines from the name",
        arguments: [
            ("  Bonus  ", "Bonus"),
            ("\tWorld\n", "World"),
            ("\n  Axess Gold \t", "Axess Gold"),
            ("İş Bankası", "İş Bankası"),
        ]
    )
    func trimsName(input: String, expected: String) throws {
        #expect(try card(input, statement: 1, due: 10).name == expected)
    }

    @Test(
        "Rejects an empty or whitespace-only name",
        arguments: ["", " ", "   ", "\n", "\t \n "]
    )
    func rejectsBlankName(name: String) {
        #expect(Card(name: name, statementDay: 1, dueDay: 10) == nil)
    }

    @Test("Accepts a name of exactly 40 characters")
    func acceptsMaxLengthName() throws {
        let name = String(repeating: "a", count: 40)
        #expect(try card(name, statement: 1, due: 10).name == name)
    }

    @Test("Counts characters, not bytes: 40 Turkish letters are accepted")
    func countsCharacters() throws {
        // "ğ" UTF-8'de 2 bayt; sınır karakter sayısıyla uygulanmalı.
        let name = String(repeating: "ğ", count: 40)
        #expect(try card(name, statement: 1, due: 10).name == name)
    }

    @Test("Rejects a name longer than 40 characters")
    func rejectsLongName() {
        #expect(Card(name: String(repeating: "a", count: 41), statementDay: 1, dueDay: 10) == nil)
        #expect(Card(name: String(repeating: "a", count: 100), statementDay: 1, dueDay: 10) == nil)
    }

    @Test("Applies the length limit after trimming")
    func lengthLimitAfterTrimming() throws {
        let name = String(repeating: "a", count: 40)
        #expect(try card("   \(name)   ", statement: 1, due: 10).name == name)
        #expect(Card(name: "  \(name)b  ", statementDay: 1, dueDay: 10) == nil)
    }

    // MARK: - Gün doğrulama

    @Test("Accepts every day from 1 to 31", arguments: 1...31)
    func acceptsValidDays(day: Int) throws {
        let c = try card(statement: day, due: day)
        #expect(c.statementDay == day)
        #expect(c.dueDay == day)
    }

    @Test(
        "Rejects a statement day outside 1...31",
        arguments: [0, -1, 32, Int.min, Int.max]
    )
    func rejectsInvalidStatementDay(day: Int) {
        #expect(Card(name: "Bonus", statementDay: day, dueDay: 10) == nil)
    }

    @Test(
        "Rejects a due day outside 1...31",
        arguments: [0, -1, 32, Int.min, Int.max]
    )
    func rejectsInvalidDueDay(day: Int) {
        #expect(Card(name: "Bonus", statementDay: 10, dueDay: day) == nil)
    }

    // MARK: - Hesap kesim günü

    @Test(
        "Clamps the statement day to the month's last day",
        arguments: [
            // (kesim günü, yıl, ay, beklenen gün)
            (31, 2026, 2, 28),   // issue örneği
            (31, 2028, 2, 29),   // artık yıl, issue örneği
            (31, 2026, 4, 30),   // issue örneği
            (31, 2026, 1, 31),
            (31, 2026, 12, 31),
            (30, 2026, 2, 28),
            (29, 2026, 2, 28),
            (29, 2028, 2, 29),
            (29, 2100, 2, 28),   // 100'e bölünür, 400'e bölünmez: artık değil
            (29, 2000, 2, 29),   // 400'e bölünür: artık
            (28, 2026, 2, 28),
            (15, 2026, 2, 15),
            (1, 2026, 2, 1),
            (30, 2026, 9, 30),
            (31, 2026, 11, 30),
        ]
    )
    func statementDayClamped(statement: Int, year: Int, month: Int, expected: Int) throws {
        let c = try card(statement: statement, due: 10)
        #expect(c.statementDay(in: ym(year, month)) == expected)
    }

    @Test("Clamping does not change the stored statement day")
    func clampingKeepsStoredDay() throws {
        let c = try card(statement: 31, due: 10)
        _ = c.statementDay(in: ym(2026, 2))
        #expect(c.statementDay == 31)
    }

    // MARK: - Son ödeme tarihi

    @Test(
        "Due date is the first due day strictly after the statement date",
        arguments: [
            // (kesim, son ödeme, kesim yılı, kesim ayı, beklenen yıl, beklenen ay, beklenen gün)
            // Issue örnekleri
            (15, 25, 2026, 3, 2026, 3, 25),
            (25, 5, 2026, 3, 2026, 4, 5),
            (10, 10, 2026, 3, 2026, 4, 10),   // aynı gün "sonra" değil
            (31, 10, 2026, 2, 2026, 3, 10),   // kesim 28'ine kayar
            (28, 30, 2026, 2, 2026, 3, 30),   // son ödeme 28'e kayar, 28 > 28 değil
            (20, 5, 2026, 12, 2027, 1, 5),    // yıl devri
            // Ek kenar durumlar
            (1, 2, 2026, 3, 2026, 3, 2),      // bir gün sonra: aynı ay
            (1, 1, 2026, 3, 2026, 4, 1),      // aynı gün, ayın ilki
            (1, 31, 2026, 2, 2026, 2, 28),    // aynı ay, son ödeme 28'e kayar ama 1'den sonra
            (1, 31, 2026, 4, 2026, 4, 30),
            (28, 29, 2028, 2, 2028, 2, 29),   // artık yıl: 29 > 28, aynı ay
            (28, 29, 2026, 2, 2026, 3, 29),   // artık değil: 29 → 28, aynı gün değil sonra
            (30, 31, 2026, 4, 2026, 5, 31),   // Nisan: 31 → 30, 30 > 30 değil
            (31, 31, 2026, 4, 2026, 5, 31),   // ikisi de 30'a kayar
            (30, 31, 2026, 3, 2026, 3, 31),   // 31 günlük ay: aynı ay
            (31, 30, 2026, 1, 2026, 2, 28),   // sonraki ayda son ödeme de kayar
            (31, 29, 2028, 1, 2028, 2, 29),   // sonraki ay artık Şubat
            (31, 29, 2100, 1, 2100, 2, 28),   // sonraki ay artık olmayan Şubat (2100)
            (31, 31, 2026, 1, 2026, 2, 28),   // Ocak 31 → Şubat 28
            (20, 31, 2026, 12, 2026, 12, 31), // Aralık içinde kalır, yıl devri yok
            (31, 31, 2026, 12, 2027, 1, 31),  // aynı gün, yıl devri
            (31, 1, 2026, 12, 2027, 1, 1),
            (15, 10, 2026, 11, 2026, 12, 10),
        ]
    )
    func dueDate(
        statement: Int, due: Int,
        year: Int, month: Int,
        expectedYear: Int, expectedMonth: Int, expectedDay: Int
    ) throws {
        let c = try card(statement: statement, due: due)
        let result = c.dueDate(forStatementIn: ym(year, month))
        #expect(result.month == ym(expectedYear, expectedMonth))
        #expect(result.day == expectedDay)
    }

    @Test("Due date is equal for equal inputs and different for different months")
    func dueDateHashable() throws {
        let c = try card(statement: 25, due: 5)
        #expect(c.dueDate(forStatementIn: ym(2026, 3)) == c.dueDate(forStatementIn: ym(2026, 3)))
        #expect(c.dueDate(forStatementIn: ym(2026, 3)) != c.dueDate(forStatementIn: ym(2026, 4)))
    }

    // MARK: - Codable

    @Test(
        "Round-trips exactly through JSON, including id",
        arguments: [
            ("Bonus", 15, 25),
            ("İş Bankası Maximum", 31, 10),
            (String(repeating: "x", count: 40), 1, 31),
            ("Quote \" and emoji 💳", 28, 28),
        ]
    )
    func roundTrips(name: String, statement: Int, due: Int) throws {
        let original = try card(name, statement: statement, due: due, id: fixedID)
        let data = try JSONEncoder().encode(Box(card: original))
        let decoded = try JSONDecoder().decode(Box.self, from: data).card
        #expect(decoded == original)
        #expect(decoded.id == fixedID)
        #expect(decoded.name == name)
        #expect(decoded.statementDay == statement)
        #expect(decoded.dueDay == due)
    }

    @Test("Decodes hand-written valid JSON")
    func decodesHandWrittenValidJSON() throws {
        // Elle yazılan JSON'un şekli doğru olmalı; aksi halde aşağıdaki throw testleri anlamsız olur.
        let decoded = try JSONDecoder().decode(Box.self, from: json(name: "Bonus", statementDay: 31, dueDay: 10)).card
        #expect(decoded.id == fixedID)
        #expect(decoded.name == "Bonus")
        #expect(decoded.statementDay == 31)
        #expect(decoded.dueDay == 10)
    }

    @Test("Decoding applies the same trimming as the initializer")
    func decodingTrimsName() throws {
        let decoded = try JSONDecoder().decode(Box.self, from: json(name: "  Bonus  ", statementDay: 1, dueDay: 10)).card
        #expect(decoded.name == "Bonus")
    }

    @Test(
        "Decoding invalid values throws",
        arguments: [
            json(name: "", statementDay: 1, dueDay: 10),
            json(name: "   ", statementDay: 1, dueDay: 10),
            json(name: String(repeating: "a", count: 41), statementDay: 1, dueDay: 10),
            json(name: "Bonus", statementDay: 0, dueDay: 10),
            json(name: "Bonus", statementDay: 32, dueDay: 10),
            json(name: "Bonus", statementDay: -5, dueDay: 10),
            json(name: "Bonus", statementDay: 10, dueDay: 0),
            json(name: "Bonus", statementDay: 10, dueDay: 32),
            json(id: "not-a-uuid", name: "Bonus", statementDay: 1, dueDay: 10),
            // Eksik alanlar
            Data(#"{"card": {"name": "Bonus", "statementDay": 1, "dueDay": 10}}"#.utf8),
            Data(#"{"card": {"id": "6F1C2A3B-4D5E-4F60-8172-93A4B5C6D7E8", "statementDay": 1, "dueDay": 10}}"#.utf8),
            Data(#"{"card": {"id": "6F1C2A3B-4D5E-4F60-8172-93A4B5C6D7E8", "name": "Bonus", "dueDay": 10}}"#.utf8),
            Data(#"{"card": {"id": "6F1C2A3B-4D5E-4F60-8172-93A4B5C6D7E8", "name": "Bonus", "statementDay": 1}}"#.utf8),
            // Yanlış tipler
            Data(#"{"card": {"id": "6F1C2A3B-4D5E-4F60-8172-93A4B5C6D7E8", "name": "Bonus", "statementDay": "1", "dueDay": 10}}"#.utf8),
            Data(#"{"card": {"id": "6F1C2A3B-4D5E-4F60-8172-93A4B5C6D7E8", "name": 42, "statementDay": 1, "dueDay": 10}}"#.utf8),
        ]
    )
    func decodingInvalidThrows(data: Data) {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Box.self, from: data)
        }
    }
}
