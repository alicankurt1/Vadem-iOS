import SwiftUI

/// Seçenekleri tek sütunlu bir listede, ince çizgilerle ayrılmış bir kartta (``FormCard``) gösterir;
/// seçilen satır işaretlenir, dokununca geri dönülür.
/// Satırlar düz metin olduğundan Dynamic Type ile büyür ve satır sınırı olmadan sarılır.
/// `onAdd` verilirse listenin sonunda "Add a card" satırı çıkar (yalnızca kart listesinde).
/// Kimlikler `identifierPrefix` ile başlar (ör. `addInstallment`): liste `<önek>.options`,
/// satırlar `<önek>.option.<sıra>` (0'dan başlar), ekleme satırı `<önek>.addCard`.
@MainActor
struct OptionList<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
    }

    let title: String
    let identifierPrefix: String
    let options: [Option]
    @Binding var selection: Value
    var onAdd: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                // Satır kimliği değerdir (benzersiz); sıra yalnızca erişilebilirlik kimliği için kullanılır.
                ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
                    Button {
                        selection = option.value
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Text(option.title)
                                .foregroundStyle(Color.vademTextPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if option.value == selection {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.vademBrand)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(option.value == selection ? .isSelected : [])
                    .accessibilityIdentifier("\(identifierPrefix).option.\(index)")
                }
            }
            .optionCardRows()
            if let onAdd {
                Section {
                    // Seçenek satırları gibi düz metin + gizli simge: Label'ın sabit simge sütunu
                    // denetimde metni "kırpılmış" gösteriyordu; düz metin Dynamic Type ile sarılır.
                    Button(action: onAdd) {
                        HStack(spacing: 8) {
                            // Ekleme satırı bağlantı gibi marka renginde.
                            Text("Add a card", bundle: .module)
                                .foregroundStyle(Color.vademBrand)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "plus")
                                .foregroundStyle(Color.vademBrand)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("\(identifierPrefix).addCard")
                }
                .optionCardRows()
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.vademBackground.ignoresSafeArea())
        .accessibilityIdentifier("\(identifierPrefix).options")
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private extension View {
    // Kart görünümü: bölümün satırları `vademSurface` zeminde, ince `vademSeparator` çizgileriyle
    // ayrılır. Liste düzeyinde verilince satırlara geçmiyor (koyu modda sistem grisi kalıyordu).
    func optionCardRows() -> some View {
        listRowBackground(Color.vademSurface)
            .listRowSeparatorTint(Color.vademSeparator)
    }
}
