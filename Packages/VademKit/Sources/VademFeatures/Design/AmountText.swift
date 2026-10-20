import SwiftUI
import VademCore

/// An amount in Turkish lira, in a rounded font with monospaced digits.
///
/// Changes animate with the numeric-text transition (off under Reduce Motion).
/// The size comes from the environment font.
@MainActor
public struct AmountText: View {
    private let money: Money

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ money: Money) {
        self.money = money
    }

    public var body: some View {
        Text(Self.format(money))
            .fontDesign(.rounded)
            .monospacedDigit()
            // Double sadece geçiş animasyonunun yönü için; gösterilen metin Decimal'den gelir.
            .contentTransition(.numericText(value: NSDecimalNumber(decimal: money.amount).doubleValue))
            .animation(Motion.animation(Motion.amount, reduceMotion: reduceMotion), value: money)
    }

    /// Formats `money` as Turkish lira (`tr_TR` style): `1234.56 → "₺1.234,56"`, `-5 → "-₺5,00"`.
    ///
    /// Pure and locale-independent: the result does not depend on the device's settings.
    public nonisolated static func format(_ money: Money) -> String {
        // NumberFormatter/ICU sürüme göre işaret ve boşluk değiştirebilir; biçim elle kurulur.
        let magnitude = money.isNegative ? -money.amount : money.amount
        let plain = NSDecimalNumber(decimal: magnitude)
            .description(withLocale: Locale(identifier: "en_US_POSIX"))
        let parts = plain.split(separator: ".", omittingEmptySubsequences: false)
        let integerDigits = Array(parts[0])
        let fraction = parts.count > 1 ? String(parts[1]) : ""
        let paddedFraction = (fraction + "00").prefix(2)

        // Binlik ayırıcı: sağdan her üç basamakta bir nokta.
        var grouped = ""
        for (index, digit) in integerDigits.enumerated() {
            if index > 0 && (integerDigits.count - index) % 3 == 0 {
                grouped.append(".")
            }
            grouped.append(digit)
        }
        return (money.isNegative ? "-" : "") + "₺" + grouped + "," + paddedFraction
    }
}

#Preview {
    VStack(alignment: .leading) {
        AmountText(Money(1234.56)).font(.largeTitle)
        AmountText(Money(-5))
    }
}
