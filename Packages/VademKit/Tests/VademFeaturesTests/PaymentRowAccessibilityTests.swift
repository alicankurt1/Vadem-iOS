import Foundation
import Testing
import VademCore
import VademFeatures

@Suite("PaymentRow.accessibilityLabel")
struct PaymentRowAccessibilityTests {

    private static func money(_ text: String) -> Money { Money(Decimal(string: text)!) }

    // Sıra: gün, başlık, (varsa) alt başlık, okunan tutar, çip metni; virgülle ayrılır.
    // Tutar "₺" olmadan, tr_TR biçiminde ve " Türk lirası" ile okunur.
    @Test("Joins day, title, subtitle, spoken amount and chip text", arguments: [
        (15, "Netflix", "Subscription" as String?, "99.99", "Today",
         "Day 15, Netflix, Subscription, 99,99 Türk lirası, Today"),
        (3, "Laptop", nil, "2500", "Later",
         "Day 3, Laptop, 2.500,00 Türk lirası, Later"),
        (31, "Rent", "", "1234567.5", "In 5 days",
         "Day 31, Rent, 1.234.567,50 Türk lirası, In 5 days"),
        (1, "Refund", nil, "-5", "Paid",
         "Day 1, Refund, eksi 5,00 Türk lirası, Paid"),
        (29, "Gym", "Leap day", "0", "Today",
         "Day 29, Gym, Leap day, 0,00 Türk lirası, Today"),
    ])
    func label(day: Int, title: String, subtitle: String?, amount: String, chip: String, expected: String) {
        let label = PaymentRow.accessibilityLabel(
            day: day, title: title, subtitle: subtitle, amount: Self.money(amount), dueTitle: chip
        )
        #expect(label == expected)
        #expect(!label.contains("₺"))
    }

    @Test("Omits the subtitle slot when it is absent")
    func defaultSubtitle() {
        let label = PaymentRow.accessibilityLabel(day: 7, title: "Water", amount: Self.money("10"), dueTitle: "Today")
        #expect(label == "Day 7, Water, 10,00 Türk lirası, Today")
    }
}
