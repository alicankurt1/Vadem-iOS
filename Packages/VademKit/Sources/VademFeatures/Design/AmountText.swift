import SwiftUI
import VademCore

/// An amount in Turkish lira (see ``AmountText/format(_:)``), in a rounded font with monospaced digits.
///
/// Changes animate with the numeric-text transition (off under Reduce Motion or `-ui-static-motion`).
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
            // Sayı asla ortadan bölünmez; yer yetmezse yazı küçülür.
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            // VoiceOver "₺" sembolü yerine okunabilir metni duyar.
            .accessibilityLabel(Self.spokenLabel(money))
            // Double sadece geçiş animasyonunun yönü için; gösterilen metin Decimal'den gelir.
            .contentTransition(.numericText(value: NSDecimalNumber(decimal: money.amount).doubleValue))
            .animation(Motion.animation(Motion.amount, reduceMotion: reduceMotion), value: money)
    }

    /// The locale whose conventions lira amounts are written in (`tr_TR`: `₺1.234,56`).
    ///
    /// Amounts are Turkish lira, so they keep the lira's home format whatever the UI language.
    public nonisolated static let amountLocale = Locale(identifier: "tr_TR")

    /// Formats `money` as Turkish lira with ``amountLocale``'s currency format:
    /// `1234.56 → "₺1.234,56"`, `-5 → "-₺5,00"`.
    ///
    /// Pure: the result does not depend on the device's settings.
    public nonisolated static func format(_ money: Money) -> String {
        // Sembol, gruplama ve işaret Foundation'ın para birimi biçiminden gelir; elle kurulmaz.
        signedAmount(money).formatted(.currency(code: "TRY").locale(amountLocale))
    }

    /// The spoken (VoiceOver) form of `money`, without symbols:
    /// `1234.56 → "1.234,56 Türk lirası"`, `-5 → "eksi 5,00 Türk lirası"`.
    ///
    /// The number is written like ``format(_:)``; the words come from the string catalog.
    public nonisolated static func spokenLabel(_ money: Money) -> String {
        let numberText = formattedMagnitude(money)
        if money.isNegative {
            return String(
                localized: "amount.spokenNegative", defaultValue: "eksi \(numberText) Türk lirası", bundle: .module,
                comment: "Spoken negative lira amount; the argument is the number without sign, e.g. 5,00"
            )
        }
        return String(
            localized: "amount.spoken", defaultValue: "\(numberText) Türk lirası", bundle: .module,
            comment: "Spoken lira amount; the argument is the number, e.g. 1.234,56"
        )
    }

    // Mutlak değer, iki ondalıkla ve amountLocale ayraçlarıyla: "1.234,56".
    nonisolated static func formattedMagnitude(_ money: Money) -> String {
        let magnitude = abs(signedAmount(money))
        return magnitude.formatted(.number.precision(.fractionLength(2)).locale(amountLocale))
    }

    // Sıfıra yuvarlanmış negatif tutar ("-0") işaretsiz sıfır olarak yazılır.
    private nonisolated static func signedAmount(_ money: Money) -> Decimal {
        money.isZero ? Decimal.zero : money.amount
    }
}

#Preview {
    VStack(alignment: .leading) {
        AmountText(Money(Decimal(123_456) / 100)).font(.largeTitle)
        AmountText(Money(-5))
    }
}
