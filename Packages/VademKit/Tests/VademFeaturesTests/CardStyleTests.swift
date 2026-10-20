import Foundation
import Testing
import VademFeatures

@Suite("CardStyle")
struct CardStyleTests {

    @Test("Has exactly the six presets from the issue")
    func sixPresets() {
        #expect(CardStyle.allCases.map(\.rawValue) == ["night", "ocean", "emerald", "sunset", "lavender", "graphite"])
    }

    @Test("Same id always gives the same style")
    func sameIdSameStyle() throws {
        for _ in 0..<200 {
            let id = UUID()
            // Aynı baytlardan yeniden kurulan UUID de aynı stili vermeli (örneğe değil baytlara bağlı).
            let copy = try #require(UUID(uuidString: id.uuidString))
            let first = CardStyle.default(for: id)
            #expect(CardStyle.default(for: id) == first)
            #expect(CardStyle.default(for: copy) == first)
        }
    }

    // Beklenen değerler uygulamadan değil, elle (Python ile) hesaplandı: UUID'nin 16 baytı
    // üzerinde standart 64-bit FNV-1a, sonucu `allCases` sırasında mod 6. Sabit id'lerin
    // sabit stil vermesi, değerin süreçten sürece değişmediğini (hashValue kullanılmadığını) gösterir.
    @Test("Fixed ids give fixed styles on every launch", arguments: [
        ("00000000-0000-0000-0000-000000000000", CardStyle.sunset),
        ("FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF", .sunset),
        ("E621E1F8-C36C-495A-93FC-0C247A3E6E5F", .sunset),
        ("123E4567-E89B-12D3-A456-426614174000", .night),
        ("6BA7B810-9DAD-11D1-80B4-00C04FD430C8", .night),
        ("F47AC10B-58CC-4372-A567-0E02B2C3D479", .lavender),
    ])
    func fixedIds(uuidString: String, expected: CardStyle) throws {
        let id = try #require(UUID(uuidString: uuidString))
        #expect(CardStyle.default(for: id) == expected)
    }

    @Test("Across many random ids every style is used, roughly evenly")
    func everyStyleUsed() {
        let count = 6_000
        var tally: [CardStyle: Int] = [:]
        for _ in 0..<count {
            tally[CardStyle.default(for: UUID()), default: 0] += 1
        }
        #expect(Set(tally.keys) == Set(CardStyle.allCases))
        // Beklenen pay ~%16,7; %10'un altı bozuk bir eşlemeyi gösterir (rastgelelikle olası değil).
        for style in CardStyle.allCases {
            #expect(tally[style, default: 0] >= count / 10, "\(style) used only \(tally[style, default: 0]) times")
        }
    }
}
