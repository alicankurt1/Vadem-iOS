import SwiftUI

/// Large tappable chips for one decision (e.g. Monthly / Yearly). Tapping a chip calls `onSelect`;
/// the step that owns the chips stores the value and advances right away (no Continue button).
///
/// The chips sit in a row when they fit, otherwise one per line (large text sizes). The selected
/// chip has the accent fill, a checkmark and the selected trait (color never carries meaning alone).
/// `stacked: true` always puts one chip per line (for steps whose row would clip at larger text sizes).
/// Identifiers: `<identifierPrefix>.chip.<index>` (from 0).
@MainActor
public struct ChoiceChips<Value: Hashable>: View {
    /// One chip: its value and title.
    public struct Option {
        public let value: Value
        public let title: String

        public init(value: Value, title: String) {
            self.value = value
            self.title = title
        }
    }

    private let options: [Option]
    private let selection: Value?
    private let identifierPrefix: String
    private let stacked: Bool
    private let onSelect: (Value) -> Void

    /// Creates chips for `options`, with `selection` highlighted (none when `nil`).
    /// `stacked` forces one chip per line at every text size.
    public init(
        options: [Option], selection: Value?, identifierPrefix: String, stacked: Bool = false,
        onSelect: @escaping (Value) -> Void
    ) {
        self.options = options
        self.selection = selection
        self.identifierPrefix = identifierPrefix
        self.stacked = stacked
        self.onSelect = onSelect
    }

    public var body: some View {
        if stacked {
            // Her zaman alt alta: metin her boyutta tam genişlikte sarılabilir, kırpılmaz.
            VStack(alignment: .leading, spacing: 10) { chips(fillsWidth: true) }
        } else {
            // Sığarsa yan yana, sığmazsa alt alta (ör. AX5).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { chips(fillsWidth: false) }
                VStack(alignment: .leading, spacing: 10) { chips(fillsWidth: true) }
            }
        }
    }

    private func chips(fillsWidth: Bool) -> some View {
        ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
            chip(option, index: index, fillsWidth: fillsWidth)
        }
    }

    private func chip(_ option: Option, index: Int, fillsWidth: Bool) -> some View {
        let isSelected = option.value == selection
        return Button {
            onSelect(option.value)
        } label: {
            HStack(spacing: 8) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
                Text(option.title)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.body.weight(.semibold))
            // Seçili çip vurgu dolgulu, üstünde onAccent; diğerleri yüzey zeminde birincil metin.
            .foregroundStyle(isSelected ? Color.vademOnAccent : Color.vademTextPrimary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 52, alignment: .leading)
            .background(isSelected ? Color.vademAccent : Color.vademSurface, in: .capsule)
            .overlay {
                if !isSelected {
                    Capsule().strokeBorder(Color.vademSeparator, lineWidth: 1)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("\(identifierPrefix).chip.\(index)")
    }
}
