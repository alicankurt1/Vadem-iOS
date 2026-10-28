import Foundation
import Testing

/// VoiceOver ipuçlarının TR ve EN çevirileri katalogda dolu ve doğru olmalı (#175).
@Suite("Accessibility hint strings")
struct AccessibilityHintStringsTests {
    private static let catalogURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()                              // VademKit
        .appendingPathComponent("Sources/VademFeatures/Resources/Localizable.xcstrings")

    private static func value(_ key: String, _ language: String) throws -> String? {
        let data = try Data(contentsOf: catalogURL)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: Any])
        let entry = strings[key] as? [String: Any]
        let loc = (entry?["localizations"] as? [String: Any])?[language] as? [String: Any]
        return (loc?["stringUnit"] as? [String: Any])?["value"] as? String
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let key: String
        let language: String
        let expected: String
        var testDescription: String { "\(key) [\(language)]" }
    }

    static let cases: [Case] = [
        Case(key: "Shows the month calendar", language: "en", expected: "Shows the month calendar"),
        Case(key: "Shows the month calendar", language: "tr", expected: "Ayın takvimini gösterir"),
        Case(key: "Opens a list", language: "en", expected: "Opens a list"),
        Case(key: "Opens a list", language: "tr", expected: "Bir liste açar"),
    ]

    @Test("Hint has the expected translation", arguments: cases)
    func translation(_ c: Case) throws {
        #expect(try Self.value(c.key, c.language) == c.expected)
    }

    @Test("Turkish hint differs from the English one", arguments: ["Shows the month calendar", "Opens a list"])
    func translated(_ key: String) throws {
        let tr = try #require(try Self.value(key, "tr"))
        let en = try #require(try Self.value(key, "en"))
        #expect(tr != en)
        #expect(!tr.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}
