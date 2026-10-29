import SwiftUI

/// A form row (title + chosen day, ``ChoiceRow`` style) that opens a bottom sheet with a wheel day picker
/// over `range` and a Done button. Shared by every place a day of the month is chosen.
///
/// The sheet opens at full height without `presentationDetents` and its content scrolls, so nothing is
/// clipped at accessibility text sizes (detents made the audit report clipped text, see ``AddFlowSheet``).
/// No animations of its own, so it is idle under `-ui-static-motion`.
/// Identifiers: the row `<identifier>`, the sheet `<identifier>.sheet`, the wheel `<identifier>.picker`,
/// the Done button `<identifier>.done`.
@MainActor
struct DayPickerRow: View {
    let title: String
    @Binding var day: Int
    let range: ClosedRange<Int>
    let identifier: String

    // Gün seçici sayfası açık mı.
    @State private var isPresented = false

    var body: some View {
        ChoiceRow(
            title: title,
            value: Self.dayText(day),
            hint: Text("Opens a day picker", bundle: .module)
        ) {
            isPresented = true
        }
        .accessibilityIdentifier(identifier)
        .sheet(isPresented: $isPresented) {
            DayPickerSheet(title: title, day: $day, range: range, identifier: identifier) {
                isPresented = false
            }
        }
    }

    // Satırda ve sayfada gösterilen gün metni ("Day 27" / "27. gün").
    static func dayText(_ day: Int) -> String {
        String(localized: "Day \(day)", bundle: .module)
    }
}

/// The sheet content of ``DayPickerRow``: title, chosen day, the wheel and a Done button, in a scroll view.
@MainActor
private struct DayPickerSheet: View {
    let title: String
    @Binding var day: Int
    let range: ClosedRange<Int>
    let identifier: String
    let onDone: () -> Void

    var body: some View {
        // Detent yok: sayfa tam boy açılır; içerik kaydırılır, AX5'te metin kırpılmaz, sarılır.
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.vademTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Text(DayPickerRow.dayText(day))
                    .font(.body)
                    .foregroundStyle(Color.vademTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Seçili gün tekerlekte de okunur; aynı bilgiyi iki kez okutmamak için gizli.
                    .accessibilityHidden(true)
                picker
                doneButton
            }
            // Yan boşluk: sol kenarda her zaman arka plan rengi kalır.
            .padding(FormLayout.spacing)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.vademBackground.ignoresSafeArea())
        .accessibilityIdentifier("\(identifier).sheet")
    }

    private var picker: some View {
        Picker(selection: $day) {
            ForEach(Array(range), id: \.self) { value in
                Text(value, format: .number)
                    .tag(value)
            }
        } label: {
            Text(title)
        }
        #if os(iOS)
        .pickerStyle(.wheel)
        #endif
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("\(identifier).picker")
    }

    private var doneButton: some View {
        Button(action: onDone) {
            Text("Done", bundle: .module)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.vademOnAccent)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.vademAccent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(identifier).done")
    }
}
