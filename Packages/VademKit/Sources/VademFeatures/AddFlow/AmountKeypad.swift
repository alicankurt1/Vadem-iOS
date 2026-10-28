import SwiftUI
import VademCore

/// A key of the ``AmountKeypad``.
public enum AmountKeypadKey: Hashable, Sendable {
    /// A digit, 0...9.
    case digit(Int)
    /// The locale's decimal separator.
    case decimalSeparator
    /// Removes the last typed character.
    case delete
}

/// What the amount keypad has typed so far, and the `Decimal` it means.
///
/// Pure value. The text uses `locale`'s decimal separator and is read with ``AmountInput/parse(_:locale:)``,
/// so the keypad accepts exactly what the forms accept. It never holds a leading zero
/// (`"0"` then `5` → `"5"`), more than ``AmountInput/maxIntegerDigits`` digits before the separator,
/// more than ``maxFractionDigits`` after it, or a second separator.
public struct AmountKeypadState: Sendable, Equatable {
    /// The most digits after the separator: kuruş.
    public static let maxFractionDigits = 2

    /// The typed text, e.g. `"1499,9"` in Turkish; empty before the first key.
    public private(set) var text: String
    /// The locale whose decimal separator the keypad types.
    public let locale: Locale

    /// Starts empty, or with `amount` written like ``AmountInput/text(for:locale:)``.
    public init(amount: Decimal? = nil, locale: Locale = .current) {
        self.locale = locale
        self.text = amount.map { AmountInput.text(for: $0, locale: locale) } ?? ""
    }

    /// The decimal separator the separator key types.
    public var decimalSeparator: String { locale.decimalSeparator ?? "." }

    /// The typed amount, or `nil` while nothing is typed.
    public var amount: Decimal? { AmountInput.parse(text, locale: locale) }

    /// `true` when the typed amount is greater than zero (the step can continue).
    public var isPositive: Bool { (amount ?? 0) > 0 }

    /// The text shown above the keys: `"₺"` and the typed text, `"₺0"` while empty.
    public var displayText: String { "₺" + (text.isEmpty ? "0" : text) }

    /// Applies `key`; keys that would break the rules above are ignored.
    public mutating func press(_ key: AmountKeypadKey) {
        let parts = text.components(separatedBy: decimalSeparator)
        let hasSeparator = parts.count > 1
        switch key {
        case .digit(let digit):
            guard (0...9).contains(digit) else { return }
            if hasSeparator {
                // Kuruştan fazla hane yazılmaz.
                guard parts[1].count < Self.maxFractionDigits else { return }
                text += String(digit)
            } else if text == "0" {
                // Baştaki sıfır yerine yeni rakam yazılır.
                text = String(digit)
            } else {
                guard parts[0].count < AmountInput.maxIntegerDigits else { return }
                text += String(digit)
            }
        case .decimalSeparator:
            guard !hasSeparator else { return }
            // Boşken ayraç "0," olarak başlar.
            text += (text.isEmpty ? "0" : "") + decimalSeparator
        case .delete:
            if !text.isEmpty { text.removeLast() }
        }
    }
}

/// The large amount keypad, the add flow's only typed input: the typed amount on top
/// (``AmountKeypadState/displayText``) and a 3 × 4 grid of keys (1–9, separator, 0, delete).
///
/// Keys are at least 56 pt tall and their labels shrink rather than clip at large text sizes.
/// VoiceOver reads the amount as "Amount, 1.499,90 Türk lirası".
/// Identifiers: `keypad.display`, `keypad.digit.<n>`, `keypad.separator`, `keypad.delete`.
@MainActor
public struct AmountKeypad: View {
    @Binding private var state: AmountKeypadState

    /// Creates the keypad editing `state`.
    public init(state: Binding<AmountKeypadState>) {
        _state = state
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text(verbatim: state.displayText)
                .font(.largeTitle.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(Color.vademTextPrimary)
                // Tutar asla bölünmez; yer yetmezse küçülür.
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, minHeight: 56)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Amount", bundle: .module))
                .accessibilityValue(AmountText.spokenLabel(Money(state.amount ?? 0)))
                .accessibilityIdentifier("keypad.display")
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(Self.rows, id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { key in
                            keyButton(key)
                        }
                    }
                }
            }
        }
    }

    // Telefon tuş takımı düzeni: 1-2-3 üstte, ayraç-0-sil altta.
    private static let rows: [[AmountKeypadKey]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.decimalSeparator, .digit(0), .delete],
    ]

    private func keyButton(_ key: AmountKeypadKey) -> some View {
        Button {
            state.press(key)
        } label: {
            keyLabel(key)
                .font(.title.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(Color.vademTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color.vademSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .modifier(KeyAccessibility(key: key))
    }

    @ViewBuilder
    private func keyLabel(_ key: AmountKeypadKey) -> some View {
        switch key {
        case .digit(let digit):
            Text(verbatim: "\(digit)")
        case .decimalSeparator:
            Text(verbatim: state.decimalSeparator)
        case .delete:
            Image(systemName: "delete.left")
        }
    }
}

// Rakamlar kendi değerini okur; ayraç ve silme tuşu adlandırılır.
private struct KeyAccessibility: ViewModifier {
    let key: AmountKeypadKey

    func body(content: Content) -> some View {
        switch key {
        case .digit(let digit):
            content
                .accessibilityIdentifier("keypad.digit.\(digit)")
        case .decimalSeparator:
            content
                .accessibilityLabel(Text("Decimal separator", bundle: .module))
                .accessibilityIdentifier("keypad.separator")
        case .delete:
            content
                .accessibilityLabel(Text("Delete", bundle: .module))
                .accessibilityIdentifier("keypad.delete")
        }
    }
}
