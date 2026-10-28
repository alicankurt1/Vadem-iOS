import Foundation
import Testing
import VademCore
import VademFeatures

@Suite("AmountKeypadState")
struct AmountKeypadStateTests {
    private static let tr = Locale(identifier: "tr_TR")
    private static let en = Locale(identifier: "en_US")

    private static func typed(_ keys: [AmountKeypadKey], locale: Locale = tr) -> AmountKeypadState {
        var state = AmountKeypadState(locale: locale)
        for key in keys { state.press(key) }
        return state
    }

    private static func digits(_ text: String) -> [AmountKeypadKey] {
        text.compactMap { $0.wholeNumberValue.map { .digit($0) } }
    }

    @Test("Starts empty with nothing typed")
    func startsEmpty() {
        let state = AmountKeypadState(locale: Self.tr)
        #expect(state.text.isEmpty)
        #expect(state.amount == nil)
        #expect(!state.isPositive)
        #expect(state.displayText == "₺0")
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let keys: [AmountKeypadKey]
        let text: String
        let amount: Decimal?
        let positive: Bool
        var testDescription: String { "\(keys) -> \(text)" }
    }

    // Türkçe ayraç ",": beklenen metin ve tutarlar elle hesaplandı.
    static let turkishCases: [Case] = [
        Case(keys: [.digit(1), .digit(5)], text: "15", amount: 15, positive: true),
        Case(keys: [.digit(1), .digit(4), .digit(9), .digit(9), .decimalSeparator, .digit(9)], text: "1499,9", amount: Decimal(string: "1499.9"), positive: true),
        Case(keys: [.digit(1), .decimalSeparator, .digit(5), .digit(0)], text: "1,50", amount: Decimal(string: "1.5"), positive: true),
        // Boşken ayraç "0," başlatır.
        Case(keys: [.decimalSeparator], text: "0,", amount: 0, positive: false),
        Case(keys: [.decimalSeparator, .digit(5)], text: "0,5", amount: Decimal(string: "0.5"), positive: true),
        // Baştaki sıfır yerine yeni rakam yazılır.
        Case(keys: [.digit(0), .digit(5)], text: "5", amount: 5, positive: true),
        Case(keys: [.digit(0), .digit(0), .digit(0)], text: "0", amount: 0, positive: false),
        // İkinci ayraç yok sayılır.
        Case(keys: [.digit(1), .decimalSeparator, .decimalSeparator, .digit(2)], text: "1,2", amount: Decimal(string: "1.2"), positive: true),
        // Üçüncü kuruş hanesi yok sayılır.
        Case(keys: [.digit(1), .decimalSeparator, .digit(2), .digit(3), .digit(4)], text: "1,23", amount: Decimal(string: "1.23"), positive: true),
        // Boşken silme bir şey yapmaz.
        Case(keys: [.delete, .delete], text: "", amount: nil, positive: false),
        Case(keys: [.digit(1), .digit(2), .delete], text: "1", amount: 1, positive: true),
        Case(keys: [.digit(1), .decimalSeparator, .delete, .decimalSeparator, .digit(5)], text: "1,5", amount: Decimal(string: "1.5"), positive: true),
        // Ayracı silince tekrar yazılabilir.
        Case(keys: [.decimalSeparator, .delete, .delete], text: "", amount: nil, positive: false),
    ]

    @Test("Types, rejects and deletes keys by the rules (Turkish)", arguments: turkishCases)
    func turkish(_ testCase: Case) {
        let state = Self.typed(testCase.keys)
        #expect(state.text == testCase.text)
        #expect(state.amount == testCase.amount)
        #expect(state.isPositive == testCase.positive)
    }

    @Test("English locale types a point")
    func englishSeparator() {
        let state = Self.typed([.digit(1), .decimalSeparator, .digit(5)], locale: Self.en)
        #expect(state.text == "1.5")
        #expect(state.decimalSeparator == ".")
        #expect(state.amount == Decimal(string: "1.5"))
    }

    @Test("Turkish locale separator is a comma")
    func turkishSeparator() {
        #expect(AmountKeypadState(locale: Self.tr).decimalSeparator == ",")
    }

    @Test("Display text shows the lira sign and the typed text")
    func displayText() {
        #expect(Self.typed([.digit(1), .digit(2), .decimalSeparator, .digit(5)]).displayText == "₺12,5")
    }

    @Test("Accepts at most maxIntegerDigits digits before the separator")
    func integerDigitLimit() {
        let max = AmountInput.maxIntegerDigits
        let full = String(repeating: "9", count: max)
        var state = Self.typed(Self.digits(full))
        #expect(state.text == full)
        state.press(.digit(1))
        #expect(state.text == full, "an extra digit must be ignored")
        // Ayraçtan sonra kuruş hâlâ yazılabilir.
        state.press(.decimalSeparator)
        state.press(.digit(5))
        #expect(state.text == full + ",5")
        #expect(state.amount != nil)
    }

    @Test("Out-of-range digits are ignored")
    func invalidDigit() {
        let state = Self.typed([.digit(1), .digit(10), .digit(-1)])
        #expect(state.text == "1")
    }

    @Test("Initial amount is written like the forms write it")
    func initialAmount() {
        let state = AmountKeypadState(amount: Decimal(string: "1499.9"), locale: Self.tr)
        #expect(state.text == "1499,9")
        #expect(state.amount == Decimal(string: "1499.9"))
        #expect(state.isPositive)
    }

    @Test("Zero amount is not positive")
    func zeroNotPositive() {
        #expect(!AmountKeypadState(amount: 0, locale: Self.tr).isPositive)
    }

    @Test("Typing after an initial amount appends")
    func appendsToInitial() {
        var state = AmountKeypadState(amount: 12, locale: Self.tr)
        state.press(.digit(3))
        #expect(state.amount == 123)
    }
}
