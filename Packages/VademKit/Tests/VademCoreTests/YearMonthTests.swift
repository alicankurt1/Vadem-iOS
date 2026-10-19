import Foundation
import Testing
import VademCore

// Test verisi için kısa yardımcı: geçersiz değer testin kendisinde bir hatadır.
private func ym(_ year: Int, _ month: Int) -> YearMonth {
    guard let value = YearMonth(year: year, month: month) else {
        fatalError("Invalid test month: \(year)-\(month)")
    }
    return value
}

// Derleme zamanı konformans kontrolü: YearMonth bu kısıtları sağlamazsa derlenmez.
private func requiresConformances<T: Sendable & Hashable & Comparable & Codable>(_: T.Type) -> Bool {
    true
}

// Belirli saat dilimine sahip Gregoryen takvim.
private func gregorian(_ timeZoneID: String) throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: timeZoneID))
    return calendar
}

// ISO 8601 UTC anından Date üretir.
private func instant(_ iso: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: iso))
}

// Codable'ı JSON nesnesi içinde test etmek için sarmalayıcı.
private struct Box: Codable, Equatable {
    let month: YearMonth
}

@Suite("YearMonth")
struct YearMonthTests {
    // MARK: - Konformanslar

    @Test("Conforms to Sendable, Hashable, Comparable, Codable")
    func conformances() {
        #expect(requiresConformances(YearMonth.self))
    }

    @Test("Equal values hash equally and deduplicate in a Set")
    func hashable() {
        let set: Set<YearMonth> = [ym(2026, 3), ym(2026, 3), ym(2027, 3)]
        #expect(set.count == 2)
        #expect(ym(2026, 3).hashValue == ym(2026, 3).hashValue)
        #expect(ym(2026, 3) != ym(2027, 3))
    }

    // MARK: - Init

    @Test("Init accepts months 1...12 and keeps components", arguments: 1...12)
    func initValid(month: Int) throws {
        let value = try #require(YearMonth(year: 2026, month: month))
        #expect(value.year == 2026)
        #expect(value.month == month)
    }

    @Test("Init returns nil outside 1...12", arguments: [0, 13, -1, -12, 24, Int.min, Int.max])
    func initInvalid(month: Int) {
        #expect(YearMonth(year: 2026, month: month) == nil)
    }

    // MARK: - adding(months:)

    @Test(
        "adding(months:) rolls over years in both directions",
        arguments: [
            // (başlangıç, eklenen, beklenen)
            (ym(2026, 11), 3, ym(2027, 2)),
            (ym(2026, 1), -1, ym(2025, 12)),
            (ym(2026, 5), 0, ym(2026, 5)),
            (ym(2026, 5), 24, ym(2028, 5)),
            (ym(2026, 5), -24, ym(2024, 5)),
            (ym(2026, 12), 1, ym(2027, 1)),
            (ym(2026, 1), -12, ym(2025, 1)),
            (ym(2026, 1), -13, ym(2024, 12)),
            (ym(2026, 12), -12, ym(2025, 12)),
            (ym(2026, 12), 12, ym(2027, 12)),
            (ym(2026, 3), -3, ym(2025, 12)),
            (ym(2026, 3), -2, ym(2026, 1)),
            (ym(2026, 3), 1200, ym(2126, 3)),
            (ym(2026, 3), -1201, ym(1926, 2)),
        ]
    )
    func adding(start: YearMonth, months: Int, expected: YearMonth) {
        #expect(start.adding(months: months) == expected)
    }

    @Test("Adding then subtracting the same amount returns the start", arguments: -30...30)
    func addingIsReversible(months: Int) {
        let start = ym(2026, 1)
        #expect(start.adding(months: months).adding(months: -months) == start)
    }

    // MARK: - months(until:)

    @Test(
        "months(until:) returns the signed distance",
        arguments: [
            (ym(2026, 11), ym(2027, 2), 3),
            (ym(2027, 2), ym(2026, 11), -3),
            (ym(2026, 5), ym(2026, 5), 0),
            (ym(2026, 1), ym(2025, 12), -1),
            (ym(2026, 12), ym(2027, 1), 1),
            (ym(2026, 5), ym(2028, 5), 24),
            (ym(2026, 1), ym(2026, 12), 11),
            (ym(2000, 1), ym(2100, 1), 1200),
        ]
    )
    func monthsUntil(from: YearMonth, to: YearMonth, expected: Int) {
        #expect(from.months(until: to) == expected)
    }

    @Test("months(until:) is the inverse of adding(months:)", arguments: -40...40)
    func monthsUntilInverse(months: Int) {
        let start = ym(2026, 7)
        #expect(start.months(until: start.adding(months: months)) == months)
    }

    // MARK: - numberOfDays

    @Test(
        "numberOfDays is correct, including leap years",
        arguments: [
            (ym(2028, 2), 29),  // 4'e bölünür: artık yıl
            (ym(2100, 2), 28),  // 100'e bölünür, 400'e bölünmez: artık değil
            (ym(2000, 2), 29),  // 400'e bölünür: artık yıl
            (ym(1900, 2), 28),
            (ym(2024, 2), 29),
            (ym(2026, 2), 28),
            (ym(2026, 1), 31),
            (ym(2026, 3), 31),
            (ym(2026, 4), 30),
            (ym(2026, 5), 31),
            (ym(2026, 6), 30),
            (ym(2026, 7), 31),
            (ym(2026, 8), 31),
            (ym(2026, 9), 30),
            (ym(2026, 10), 31),
            (ym(2026, 11), 30),
            (ym(2026, 12), 31),
        ]
    )
    func numberOfDays(month: YearMonth, expected: Int) {
        #expect(month.numberOfDays == expected)
    }

    // MARK: - init(date:calendar:)

    @Test(
        "init(date:calendar:) uses the calendar's time zone",
        arguments: [
            // Aynı an, saat dilimine göre farklı aya düşer.
            ("2026-03-31T23:30:00Z", "UTC", ym(2026, 3)),
            ("2026-03-31T23:30:00Z", "Europe/Istanbul", ym(2026, 4)),  // UTC+3
            ("2026-01-01T05:00:00Z", "UTC", ym(2026, 1)),
            ("2026-01-01T05:00:00Z", "Pacific/Honolulu", ym(2025, 12)),  // UTC-10
            ("2028-02-29T12:00:00Z", "UTC", ym(2028, 2)),
            ("2026-12-31T21:00:00Z", "Europe/Istanbul", ym(2027, 1)),  // tam ay sınırı
            ("2026-12-31T20:59:59Z", "Europe/Istanbul", ym(2026, 12)),
        ]
    )
    func initFromDate(iso: String, timeZoneID: String, expected: YearMonth) throws {
        let date = try instant(iso)
        let calendar = try gregorian(timeZoneID)
        #expect(YearMonth(date: date, calendar: calendar) == expected)
    }

    // MARK: - Comparable

    @Test(
        "Comparable orders chronologically",
        arguments: [
            (ym(2026, 12), ym(2027, 1)),
            (ym(2026, 1), ym(2026, 2)),
            (ym(2025, 12), ym(2026, 1)),
            (ym(2026, 2), ym(2026, 11)),  // aylar sayısal, string değil
            (ym(1999, 12), ym(2000, 1)),
        ]
    )
    func ordering(earlier: YearMonth, later: YearMonth) {
        #expect(earlier < later)
        #expect(!(later < earlier))
        #expect(later > earlier)
    }

    @Test("Equal months are not less than each other")
    func orderingEqual() {
        #expect(!(ym(2026, 5) < ym(2026, 5)))
        #expect(ym(2026, 5) <= ym(2026, 5))
    }

    @Test("Sorting yields chronological order")
    func sorting() {
        let unsorted = [ym(2027, 1), ym(2026, 11), ym(2026, 2), ym(2025, 12), ym(2026, 12)]
        let expected = [ym(2025, 12), ym(2026, 2), ym(2026, 11), ym(2026, 12), ym(2027, 1)]
        #expect(unsorted.sorted() == expected)
    }

    // MARK: - Codable

    @Test(
        "Encodes as a YYYY-MM string",
        arguments: [
            (ym(2026, 3), "2026-03"),
            (ym(2026, 12), "2026-12"),
            (ym(2027, 1), "2027-01"),
        ]
    )
    func encodes(value: YearMonth, expected: String) throws {
        let data = try JSONEncoder().encode(Box(month: value))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json == #"{"month":"\#(expected)"}"#)
    }

    @Test("Decodes a YYYY-MM string")
    func decodes() throws {
        let data = Data(#"{"month":"2026-03"}"#.utf8)
        let box = try JSONDecoder().decode(Box.self, from: data)
        #expect(box.month == ym(2026, 3))
    }

    @Test(
        "Round-trips exactly through JSON",
        arguments: [ym(2026, 3), ym(2026, 12), ym(2025, 1), ym(2000, 2), ym(2100, 11)]
    )
    func roundTrip(value: YearMonth) throws {
        let data = try JSONEncoder().encode(Box(month: value))
        let decoded = try JSONDecoder().decode(Box.self, from: data)
        #expect(decoded.month == value)
        #expect(try JSONEncoder().encode(decoded) == data)
    }

    @Test(
        "Decoding an invalid string throws",
        arguments: [
            "2026-13", "2026-3", "abc",
            "2026-00", "", "2026", "2026-", "-03",
            "2026/03", "2026-03-01", " 2026-03", "2026-03 ",
            "26-03", "2026-1a",
        ]
    )
    func decodeInvalidThrows(text: String) throws {
        let data = try JSONEncoder().encode(["month": text])
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Box.self, from: data)
        }
    }

    // MARK: - Desteklenen yıl aralığı (1...9999)

    @Test("Supported years are 1...9999")
    func supportedYears() {
        #expect(YearMonth.supportedYears == 1...9999)
    }

    @Test("Init returns nil outside the supported years", arguments: [0, -1, 10000, Int.min, Int.max])
    func initInvalidYear(year: Int) {
        #expect(YearMonth(year: year, month: 1) == nil)
        #expect(YearMonth(year: year, month: 12) == nil)
    }

    @Test("Init accepts the first and last supported year", arguments: [(1, 1), (1, 12), (9999, 1), (9999, 12)])
    func initBoundaryYear(year: Int, month: Int) throws {
        let value = try #require(YearMonth(year: year, month: month))
        #expect(value.year == year)
        #expect(value.month == month)
    }

    @Test(
        "Round-trips exactly at the year boundaries",
        arguments: [(ym(1, 1), "0001-01"), (ym(9999, 12), "9999-12")]
    )
    func roundTripBoundaries(value: YearMonth, text: String) throws {
        let data = try JSONEncoder().encode(Box(month: value))
        #expect(String(data: data, encoding: .utf8) == #"{"month":"\#(text)"}"#)
        let decoded = try JSONDecoder().decode(Box.self, from: data)
        #expect(decoded.month == value)
    }

    @Test("Decoding a year outside the supported range throws", arguments: ["0000-01", "10000-01"])
    func decodeOutOfRangeYearThrows(text: String) throws {
        let data = try JSONEncoder().encode(["month": text])
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Box.self, from: data)
        }
    }

    @Test(
        "adding(months:) reaches the edges of the supported years",
        arguments: [
            (ym(9999, 11), 1, ym(9999, 12)),
            (ym(1, 2), -1, ym(1, 1)),
            (ym(9998, 12), 12, ym(9999, 12)),
            (ym(2, 1), -12, ym(1, 1)),
            (ym(1, 1), 9999 * 12 - 1, ym(9999, 12)),
        ]
    )
    func addingToEdges(start: YearMonth, months: Int, expected: YearMonth) {
        #expect(start.adding(months: months) == expected)
    }

    // Exit test'ler yalnızca macOS'ta var; iOS derlemesinde atlanır.
    #if os(macOS)
    @Test("adding(months:) traps past 9999-12")
    func addingPastUpperBoundTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = YearMonth(year: 9999, month: 12)!.adding(months: 1)
        }
    }

    @Test("adding(months:) traps before 0001-01")
    func addingPastLowerBoundTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = YearMonth(year: 1, month: 1)!.adding(months: -1)
        }
    }
    #endif

    // MARK: - Gregoryen olmayan takvim

    @Test(
        "init(date:calendar:) yields the Gregorian month for non-Gregorian calendars",
        arguments: [
            ("2026-03-15T12:00:00Z", Calendar.Identifier.hebrew, "UTC", ym(2026, 3)),
            ("2026-03-15T12:00:00Z", Calendar.Identifier.persian, "UTC", ym(2026, 3)),
            ("2026-03-15T12:00:00Z", Calendar.Identifier.japanese, "UTC", ym(2026, 3)),
            ("2026-03-15T12:00:00Z", Calendar.Identifier.islamicUmmAlQura, "UTC", ym(2026, 3)),
            // Takvimin saat dilimi yine ayı belirler.
            ("2026-03-31T23:30:00Z", Calendar.Identifier.persian, "Europe/Istanbul", ym(2026, 4)),
            ("2026-01-01T05:00:00Z", Calendar.Identifier.hebrew, "Pacific/Honolulu", ym(2025, 12)),
        ]
    )
    func initFromDateNonGregorian(
        iso: String, identifier: Calendar.Identifier, timeZoneID: String, expected: YearMonth
    ) throws {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = try #require(TimeZone(identifier: timeZoneID))
        #expect(YearMonth(date: try instant(iso), calendar: calendar) == expected)
    }

    @Test("Decoding a non-string value throws")
    func decodeNonStringThrows() {
        let data = Data(#"{"month":202603}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Box.self, from: data)
        }
    }
}
