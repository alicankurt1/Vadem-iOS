import SwiftUI

// Formlarda ortak satırlar: alan bölümü (+ hata metni) ve seçim listesini açan satır.

/// Bir alanı ve (varsa) altındaki hata metnini aynı bölümde gösterir.
/// Hata kimliği `<errorIdentifier>` olur (ör. `addInstallment.title.error`).
@MainActor
struct FormFieldSection<Content: View>: View {
    let errorMessage: String?
    let errorIdentifier: String
    @ViewBuilder let content: Content

    var body: some View {
        Section {
            content
            if let errorMessage {
                FieldErrorLabel(message: errorMessage)
                    .accessibilityIdentifier(errorIdentifier)
            }
        }
        .listRowBackground(Color.vademSurface)
    }
}

/// Alanın altındaki hata metni.
@MainActor
struct FieldErrorLabel: View {
    let message: String

    var body: some View {
        // Hata yalnızca renkle değil, simge ve metinle de belirtilir.
        Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(Color.vademTextPrimary)
    }
}

/// Dokununca seçim listesini iten satır; ok simgesi metin stiliyle Dynamic Type'a göre büyür.
/// Satır bizim çizdiğimiz bir düğme: hazır menü ve gezinme bağlantısı oku denetimde
/// "Dynamic Type desteklenmiyor" sayılıyordu.
@MainActor
struct ChoiceRow: View {
    let title: String
    let value: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                label
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.vademTextSecondary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens a list")
    }

    // Başlık ve değer normal boyutlarda yan yana, erişilebilirlik boyutlarında alt alta durur.
    // ViewThatFits yerine AnyLayout: metinlerin kimliği boyut değişince korunur; aksi halde
    // denetim yeni oluşan metni "Dynamic Type kısmen desteklenmiyor" sayıyor.
    private var label: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Text(title)
                .foregroundStyle(Color.vademTextPrimary)
                .frame(maxWidth: stacked ? .infinity : nil, alignment: .leading)
            if !stacked {
                Spacer(minLength: 8)
            }
            Text(value)
                .foregroundStyle(Color.vademTextSecondary)
                .frame(maxWidth: stacked ? .infinity : nil, alignment: .leading)
        }
        .multilineTextAlignment(.leading)
        .contentShape(Rectangle())
    }
}

/// Düzenleme formunun en altındaki silme bölümü: dokununca `isConfirming` açılır.
/// Onay, formun kendisine ``SwiftUI/View/deleteConfirmation(isPresented:title:message:identifierPrefix:onDelete:)``
/// ile bağlanır. Kimlik: düğme `<identifierPrefix>.delete`.
@MainActor
struct DeleteSection: View {
    let title: String
    let identifierPrefix: String
    @Binding var isConfirming: Bool

    var body: some View {
        Section {
            // Label yerine düz metin + gizli simge: Label'ın sabit simge sütunu denetimde metni
            // "kırpılmış" gösteriyordu; düz metin Dynamic Type ile sarılır, satır yüksekliği serbest.
            Button(role: .destructive) {
                isConfirming = true
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "trash")
                        .accessibilityHidden(true)
                }
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("\(identifierPrefix).delete")
        }
        .listRowBackground(Color.vademSurface)
    }
}

extension View {
    /// Silme onayını bu görünüme bağlar. Kimlikler: onay `<identifierPrefix>.delete.confirm`,
    /// vazgeç `<identifierPrefix>.delete.cancel`.
    func deleteConfirmation(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        identifierPrefix: String,
        onDelete: @escaping () -> Void
    ) -> some View {
        // Onay düğmeye değil tüm forma bağlanır: iOS 26'da diyalog bağlandığı görünümden açılır;
        // küçük bir düğmeye bağlıyken dar bir açılır pencere (popover) oluyor, Vazgeç düğmesi
        // gizleniyor ve düğme kimliği iki kez görünüyordu. Forma bağlıyken alttan açılan sayfa olur.
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
                .accessibilityIdentifier("\(identifierPrefix).delete.confirm")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("\(identifierPrefix).delete.cancel")
        } message: {
            Text(message)
        }
    }
}
